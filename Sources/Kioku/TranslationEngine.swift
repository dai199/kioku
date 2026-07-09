import Foundation
import NaturalLanguage

struct TranslationRequest: Sendable {
    let text: String
    /// ISO言語コード（"en" / "ja"）。SPECどおり言語ペアは最初から抽象化しておく。
    let sourceLanguage: String
    let targetLanguage: String
    /// 「別の訳」再生成時、既に提示した訳（これらとは違う訳を返してもらう）
    var alternativesToAvoid: [String] = []
}

/// 翻訳エンジンの抽象化。将来Apple Translation（オフライン）や
/// オンデバイスLLMへ差し替え・併用できるようにしておく。
protocol TranslationEngine: Sendable {
    func translate(_ request: TranslationRequest) async throws -> String
    /// 逐次テキスト片を返すストリーミング翻訳。
    func translateStream(_ request: TranslationRequest) -> AsyncThrowingStream<String, Error>
}

extension TranslationEngine {
    /// ストリーミング未対応エンジンは全文を1回で返す。
    func translateStream(_ request: TranslationRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let engine = self
            Task {
                do {
                    continuation.yield(try await engine.translate(request))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

enum LanguageDetector {
    /// 選択テキストの言語から翻訳方向を決める。
    /// 日本語なら日→英（ライティング支援）、それ以外は英→日（読解支援）とみなす。
    static func direction(for text: String) -> (source: String, target: String) {
        // ひらがな・カタカナが1文字でもあれば日本語とみなす。
        // 英語の用語が多く混ざった日本語文で、NLの判定が英語に倒れるのを防ぐ
        let containsKana = text.unicodeScalars.contains { (0x3040...0x30FF).contains($0.value) }
        if containsKana {
            return ("ja", "en")
        }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(String(text.prefix(200)))
        if recognizer.dominantLanguage == .japanese {
            return ("ja", "en")
        }
        return ("en", "ja")
    }
}
