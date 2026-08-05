import Foundation
import os

/// 翻訳パスのログ。ポップアップは失敗を「翻訳中…」のまま抱えることがあるため、
/// どこで止まったかを後から追えるようにしておく。本文は記録しない（長さのみ）。
let translationLogger = Logger(subsystem: "com.daikitagami.kioku", category: "translate")

enum GeminiError: LocalizedError {
    case missingAPIKey
    case apiError(status: Int, message: String)
    case emptyResult

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Gemini APIキーが設定されていません"
        case .apiError(let status, let message):
            return "APIエラー (\(status)): \(message)"
        case .emptyResult:
            return "生成結果が空でした"
        }
    }
}

/// Gemini API（generateContent）の薄いクライアント。翻訳と週次分析の双方から使う。
struct GeminiClient: Sendable {
    /// 週次分析など、時間がかかってよい呼び出しの既定値
    static let defaultTimeout: TimeInterval = 90

    let apiKey: String
    let model: String
    /// リクエストのタイムアウト。ストリーミングでは「データが来ない時間」の上限として効く。
    /// 用途で大きく変わるので呼び出し側が決める（翻訳は短く、週次分析は長く）。
    var timeout: TimeInterval = defaultTimeout

    func generateText(
        prompt: String,
        temperature: Double,
        jsonResponse: Bool = false
    ) async throws -> String {
        guard !apiKey.isEmpty else { throw GeminiError.missingAPIKey }
        guard let url = URL(
            string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent"
        ) else { throw URLError(.badURL) }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        urlRequest.timeoutInterval = timeout

        let body = GenerateContentRequest(
            contents: [.init(parts: [.init(text: prompt)])],
            generationConfig: .init(
                temperature: temperature,
                responseMimeType: jsonResponse ? "application/json" : nil
            )
        )
        urlRequest.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard http.statusCode == 200 else {
            let message = (try? JSONDecoder().decode(APIErrorResponse.self, from: data))?
                .error.message ?? String(data: data, encoding: .utf8) ?? "不明なエラー"
            throw GeminiError.apiError(status: http.statusCode, message: message)
        }

        let decoded = try JSONDecoder().decode(GenerateContentResponse.self, from: data)
        let text = decoded.candidates?.first?.content?.parts?
            .compactMap(\.text)
            .joined() ?? ""
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw GeminiError.emptyResult }
        return trimmed
    }

    /// SSEストリーミング（streamGenerateContent?alt=sse）でテキスト片を逐次返す。
    func streamText(
        prompt: String,
        temperature: Double
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let client = self
            Task {
                do {
                    guard !client.apiKey.isEmpty else { throw GeminiError.missingAPIKey }
                    guard let url = URL(
                        string: "https://generativelanguage.googleapis.com/v1beta/models/\(client.model):streamGenerateContent?alt=sse"
                    ) else { throw URLError(.badURL) }

                    var urlRequest = URLRequest(url: url)
                    urlRequest.httpMethod = "POST"
                    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    urlRequest.setValue(client.apiKey, forHTTPHeaderField: "x-goog-api-key")
                    urlRequest.timeoutInterval = client.timeout
                    let body = GenerateContentRequest(
                        contents: [.init(parts: [.init(text: prompt)])],
                        generationConfig: .init(temperature: temperature, responseMimeType: nil)
                    )
                    urlRequest.httpBody = try JSONEncoder().encode(body)

                    translationLogger.log(
                        "ストリーム要求 model=\(client.model, privacy: .public)"
                    )
                    let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
                    guard let http = response as? HTTPURLResponse else {
                        throw URLError(.badServerResponse)
                    }
                    translationLogger.log("HTTP \(http.statusCode, privacy: .public)")
                    guard http.statusCode == 200 else {
                        var errorBody = ""
                        for try await line in bytes.lines {
                            errorBody += line
                            if errorBody.count > 2000 { break }
                        }
                        let message = (try? JSONDecoder().decode(
                            APIErrorResponse.self, from: Data(errorBody.utf8)
                        ))?.error.message ?? errorBody
                        throw GeminiError.apiError(status: http.statusCode, message: message)
                    }

                    var chunkCount = 0
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        guard payload != "[DONE]" else { break }
                        guard let chunk = try? JSONDecoder().decode(
                            GenerateContentResponse.self, from: Data(payload.utf8)
                        ) else { continue }
                        let text = chunk.candidates?.first?.content?.parts?
                            .compactMap(\.text)
                            .joined() ?? ""
                        if !text.isEmpty {
                            chunkCount += 1
                            continuation.yield(text)
                        }
                    }
                    translationLogger.log(
                        "ストリーム終了 chunks=\(chunkCount, privacy: .public)"
                    )
                    continuation.finish()
                } catch {
                    translationLogger.error(
                        "ストリーム失敗: \(error.localizedDescription, privacy: .public)"
                    )
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

/// Geminiを使う翻訳エンジン。BYOK前提。
struct GeminiEngine: TranslationEngine {
    /// 翻訳プロンプトのバージョン。プロンプトを変更したら必ず上げる
    /// （選好シグナルと突き合わせて、どの変更が品質に効いたか追跡するため）。
    static let promptVersion = "2026-07-06.1"

    /// 翻訳のタイムアウト。選択してすぐ答えが欲しいポップアップで、
    /// 通信が固まったまま何十秒も「翻訳中…」を見せないための上限。
    /// 早く失敗させて「再試行」で作り直せるほうが、待たせ続けるより体験がよい。
    static let timeout: TimeInterval = 20

    let apiKey: String
    let model: String

    private var client: GeminiClient {
        GeminiClient(apiKey: apiKey, model: model, timeout: Self.timeout)
    }

    func translate(_ request: TranslationRequest) async throws -> String {
        try await client.generateText(
            prompt: prompt(for: request),
            // 再生成時はバリエーションを出したいので温度を上げる
            temperature: request.alternativesToAvoid.isEmpty ? 0.2 : 0.9
        )
    }

    func translateStream(_ request: TranslationRequest) -> AsyncThrowingStream<String, Error> {
        client.streamText(
            prompt: prompt(for: request),
            temperature: request.alternativesToAvoid.isEmpty ? 0.2 : 0.9
        )
    }

    private func prompt(for request: TranslationRequest) -> String {
        let names = ["en": "English", "ja": "Japanese"]
        let source = names[request.sourceLanguage] ?? request.sourceLanguage
        let target = names[request.targetLanguage] ?? request.targetLanguage

        var instruction = """
        Translate the following \(source) text into natural \(target). \
        Preserve the tone and register of the original. \
        Output only the translation, with no explanations, quotation marks, or notes.
        """
        if !request.alternativesToAvoid.isEmpty {
            let previous = request.alternativesToAvoid
                .map { "- \($0)" }
                .joined(separator: "\n")
            instruction += """
            \n
            You have already suggested the following translations. \
            Provide a clearly different but equally natural alternative:
            \(previous)
            """
        }
        return instruction + "\n\n" + request.text
    }
}

// MARK: - Gemini API DTO

private struct GenerateContentRequest: Encodable {
    struct Content: Encodable {
        struct Part: Encodable {
            let text: String
        }
        let parts: [Part]
    }
    struct GenerationConfig: Encodable {
        let temperature: Double
        let responseMimeType: String?
    }
    let contents: [Content]
    let generationConfig: GenerationConfig
}

private struct GenerateContentResponse: Decodable {
    struct Candidate: Decodable {
        struct Content: Decodable {
            struct Part: Decodable {
                let text: String?
            }
            let parts: [Part]?
        }
        let content: Content?
    }
    let candidates: [Candidate]?
}

private struct APIErrorResponse: Decodable {
    struct APIError: Decodable {
        let message: String
    }
    let error: APIError
}
