import Foundation

/// プロンプトを組み立てるエンジンが複数あるので、文言はここに一本化する。
/// エンジンごとに別の文言だと、品質を比べたときに何を比べているのか分からなくなる。
enum TranslationPrompt {
    static func translate(for request: TranslationRequest) -> String {
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
        // 方向指定はユーザーの明示的な要求なので、最後に置いて最も強く効かせる
        if let direction = request.styleDirection {
            instruction += "\n\n" + direction.instruction
        }
        return instruction + "\n\n" + request.text
    }

    static func explain(for request: ExplanationRequest) -> String {
        // 読解（英→日）は「なぜこう書かれているか」、作文（日→英）は
        // 「なぜこう訳したか」を知りたい。方向で聞くことが変わる
        let isWriting = request.sourceLanguage == "ja"
        let focus = isWriting
            ? """
            The user wrote the Japanese and wants to send the English. Explain why this \
            English phrasing works: the grammar or structure chosen, the register it conveys, \
            and any wording that a Japanese speaker would be likely to get wrong here.
            """
            : """
            The user is reading the English and wants to understand it. Explain the grammar or \
            structure that makes it hard to parse, any idioms or set phrases, and nuance that \
            the Japanese translation cannot carry.
            """

        return """
        You are an English tutor for a Japanese learner.

        \(focus)

        Write in Japanese. Use 2 to 4 short bullet points, each starting with "・". \
        Be concrete and refer to the actual words in the text. \
        No preamble, no restatement of the translation, no headings.

        English: \(isWriting ? request.translatedText : request.sourceText)
        Japanese: \(isWriting ? request.sourceText : request.translatedText)
        """
    }
}
