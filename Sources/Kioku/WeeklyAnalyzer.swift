import Foundation

/// AIによる週次分析の結果。
struct WeeklyAnalysis: Codable, Sendable {
    struct Pattern: Codable, Sendable {
        let title: String
        let description: String
        let examples: [String]?
    }
    struct CardProposal: Codable, Sendable {
        let front: String
        let back: String
        let reason: String?
        let logId: Int64?
    }
    let summary: String
    let patterns: [Pattern]
    let cards: [CardProposal]
}

/// レポートとしてDBに保存する内容（自前集計の統計＋AI分析）。
struct WeeklyReportContent: Codable, Sendable {
    struct Stats: Codable, Sendable {
        let total: Int
        let reading: Int
        let writing: Int
        let topApps: [String]
    }
    let stats: Stats
    let analysis: WeeklyAnalysis
}

/// 過去1週間の翻訳ログを上位モデルで分析し、
/// つまずきパターンとSRSカード候補を抽出する。
struct WeeklyAnalyzer: Sendable {
    let client: GeminiClient

    func analyze(logs: [TranslationLog]) async throws -> WeeklyAnalysis {
        let raw = try await client.generateText(
            prompt: Self.buildPrompt(logs: logs),
            temperature: 0.3,
            jsonResponse: true
        )
        let data = Self.extractJSONData(raw)
        do {
            return try JSONDecoder().decode(WeeklyAnalysis.self, from: data)
        } catch {
            throw AnalyzerError.invalidResponse(String(raw.prefix(300)))
        }
    }

    enum AnalyzerError: LocalizedError {
        case invalidResponse(String)
        var errorDescription: String? {
            switch self {
            case .invalidResponse(let excerpt):
                return "分析結果のJSONを解釈できませんでした: \(excerpt)"
            }
        }
    }

    private struct LogEntry: Encodable {
        let id: Int64?
        let direction: String
        let source: String
        let translation: String
        let app: String?
    }

    static func buildPrompt(logs: [TranslationLog]) -> String {
        let entries = logs.prefix(300).map { log in
            LogEntry(
                id: log.id,
                direction: log.direction,
                source: String(log.sourceText.prefix(200)),
                translation: String(log.translatedText.prefix(200)),
                app: log.sourceApp
            )
        }
        let logsJSON = (try? JSONEncoder().encode(Array(entries)))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"

        return """
        あなたは日本人英語学習者専属の学習コーチです。
        以下はユーザーの過去1週間の翻訳ログ（JSON）です。
        - direction "reading": ユーザーが読んでいて意味を確認した英文（source=英文, translation=日本語訳）
        - direction "writing": ユーザーが英語で言いたかった内容（source=日本語, translation=採用した英文）

        次の2つを行い、指定のJSONだけを出力してください。

        1. ユーザーが繰り返しつまずいている文法・語彙・表現のパターンを重要度順に最大5件抽出する。
        2. 覚える価値が高いSRSカード候補を最大10件選ぶ。front=日本語（意味・言いたいこと）、back=自然な英文。
           - 日常やビジネスで再利用しやすい汎用的な表現を優先する
           - 固有名詞や文脈依存が強すぎるもの、極端に長い文は避ける
           - 元になったログのidをlogIdに入れる（対応するものがなければnull）

        出力JSONスキーマ:
        {
          "summary": "今週の学習の総評。日本語で2〜3文。",
          "patterns": [{"title": "短い見出し", "description": "説明（日本語）", "examples": ["ログ中の実例"]}],
          "cards": [{"front": "日本語", "back": "English sentence", "reason": "選定理由（日本語）", "logId": 123}]
        }

        翻訳ログ:
        \(logsJSON)
        """
    }

    /// モデルがMarkdownのコードフェンスで囲んで返した場合に備えて剥がす。
    static func extractJSONData(_ raw: String) -> Data {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            text = lines
                .dropFirst()
                .prefix(while: { !$0.hasPrefix("```") })
                .joined(separator: "\n")
        }
        return Data(text.utf8)
    }
}
