import Foundation
import FoundationModels

/// Apple Intelligence のオンデバイスLLM（macOS 26以降・要 Apple Intelligence 有効化）。
///
/// Apple翻訳と違いプロンプトを渡せるので、方向指定も「別の訳」も解説も成立する。
/// テキストは端末から出ず、費用もかからない。「送信ゼロ」の枠内での最良の選択肢。
@available(macOS 26.0, *)
struct FoundationModelsEngine: TranslationEngine {
    let promptVersion = "apple-fm/1"
    let capabilities = EngineCapabilities.full

    /// 利用できるかは実行時にしか分からない（Apple Intelligenceが無効、
    /// モデル未ダウンロード、非対応言語などで落ちる）。設定画面での出し分けに使う。
    static var availabilityMessage: String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(let reason):
            switch reason {
            case .appleIntelligenceNotEnabled:
                return "システム設定の「Apple IntelligenceとSiri」で有効にしてください。"
            case .modelNotReady:
                return "モデルの準備中です。しばらく待ってからお試しください。"
            case .deviceNotEligible:
                return "このMacはApple Intelligenceに対応していません。"
            @unknown default:
                return "Apple Intelligenceを利用できません。"
            }
        @unknown default:
            return "Apple Intelligenceを利用できません。"
        }
    }

    func translate(_ request: TranslationRequest) async throws -> String {
        try await respond(to: TranslationPrompt.translate(for: request))
    }

    func explain(_ request: ExplanationRequest) async throws -> String {
        try await respond(to: TranslationPrompt.explain(for: request))
    }

    private func respond(to prompt: String) async throws -> String {
        if let message = Self.availabilityMessage {
            throw FoundationModelsError.unavailable(message)
        }
        let session = LanguageModelSession()
        let text = try await session.respond(to: prompt).content
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw FoundationModelsError.emptyResult }
        return text
    }
}

enum FoundationModelsError: LocalizedError {
    case unavailable(String)
    case emptyResult

    var errorDescription: String? {
        switch self {
        case .unavailable(let message): return message
        case .emptyResult: return "生成結果が空でした。"
        }
    }
}
