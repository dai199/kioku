import Testing
@testable import Kioku

/// 翻訳方向の自動判定。
/// 判定を外すと「日本語を選んだのに日本語訳が出る」ため、体験への影響が大きい。
@Suite("言語判定")
struct LanguageDetectorTests {
    @Test("かなを含む文は日→英（ライティング支援）", arguments: [
        "これはテストです。",
        "テスト",
        // 英語の用語が多く混ざった日本語文。NLの判定が英語に倒れる問題への回帰テスト
        "このAPIはdeprecatedなので、新しいendpointにmigrateしてください",
        "Slackで共有しておきます",
    ])
    func japaneseGoesToEnglish(text: String) {
        let direction = LanguageDetector.direction(for: text)
        #expect(direction.source == "ja")
        #expect(direction.target == "en")
    }

    @Test("英文は英→日（読解支援）", arguments: [
        "This is a pen.",
        "The quick brown fox jumps over the lazy dog.",
    ])
    func englishGoesToJapanese(text: String) {
        let direction = LanguageDetector.direction(for: text)
        #expect(direction.source == "en")
        #expect(direction.target == "ja")
    }
}
