import Testing
@testable import Kioku

/// 翻訳プロンプトの組み立て。
/// 方向指定は「ユーザーが明示した要求」なので、確実にプロンプトへ届く必要がある。
/// ここが黙って落ちると、方向を選んでも何も変わらないのに気づけない。
@Suite("翻訳プロンプトの組み立て")
struct TranslationPromptTests {
    private let engine = GeminiEngine(apiKey: "", model: "")

    private func prompt(
        text: String = "確認します",
        source: String = "ja",
        target: String = "en",
        avoiding: [String] = [],
        direction: StyleDirection? = nil
    ) -> String {
        engine.prompt(for: TranslationRequest(
            text: text,
            sourceLanguage: source,
            targetLanguage: target,
            alternativesToAvoid: avoiding,
            styleDirection: direction
        ))
    }

    @Test("原文と言語ペアが入る")
    func includesTextAndLanguages() {
        let result = prompt()
        #expect(result.contains("確認します"))
        #expect(result.contains("Japanese"))
        #expect(result.contains("English"))
    }

    @Test("方向指定がなければスタイルの指示は入らない")
    func noStyleInstructionWithoutDirection() {
        let result = prompt()
        for direction in StyleDirection.allCases {
            #expect(!result.contains(direction.instruction))
        }
    }

    @Test("方向を指定すると、その指示だけが入る", arguments: StyleDirection.allCases)
    func includesOnlyTheRequestedDirection(direction: StyleDirection) {
        let result = prompt(direction: direction)
        #expect(result.contains(direction.instruction))
        for other in StyleDirection.allCases where other != direction {
            #expect(!result.contains(other.instruction))
        }
    }

    @Test("既出の訳の回避と方向指定は同時に効く")
    func combinesAvoidanceAndDirection() {
        let result = prompt(avoiding: ["Let me check."], direction: .casual)
        #expect(result.contains("Let me check."))
        #expect(result.contains(StyleDirection.casual.instruction))
    }

    // MARK: - 解説プロンプト

    private func explanation(source: String, target: String) -> String {
        GeminiEngine.explanationPrompt(for: ExplanationRequest(
            sourceText: source == "ja" ? "確認します" : "Let me check.",
            translatedText: source == "ja" ? "Let me check." : "確認します",
            sourceLanguage: source,
            targetLanguage: target
        ))
    }

    @Test("解説は英文と日本語文の両方を渡す（方向によらず取り違えない）",
          arguments: [("ja", "en"), ("en", "ja")])
    func explanationIncludesBothTexts(pair: (source: String, target: String)) {
        let result = explanation(source: pair.source, target: pair.target)
        #expect(result.contains("English: Let me check."))
        #expect(result.contains("Japanese: 確認します"))
    }

    @Test("読解（英→日）では、英文を理解するための観点を聞く")
    func explanationForReading() {
        let result = explanation(source: "en", target: "ja")
        #expect(result.contains("reading the English"))
        #expect(!result.contains("wants to send the English"))
    }

    @Test("作文（日→英）では、英文を送る側の観点を聞く")
    func explanationForWriting() {
        let result = explanation(source: "ja", target: "en")
        #expect(result.contains("wants to send the English"))
        #expect(!result.contains("reading the English"))
    }

    @Test("方向の指示は原文より前に置く（末尾の原文が指示に埋もれないように）")
    func directionComesBeforeSourceText() {
        let result = prompt(text: "確認します", direction: .formal)
        let instructionIndex = result.range(of: StyleDirection.formal.instruction)?.lowerBound
        let textIndex = result.range(of: "確認します")?.lowerBound
        #expect(instructionIndex != nil)
        #expect(textIndex != nil)
        if let instructionIndex, let textIndex {
            #expect(instructionIndex < textIndex)
        }
    }
}
