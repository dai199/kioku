import Foundation

/// 翻訳する価値のある選択かを判定する。
/// URL・ドメイン・ファイル名・メールアドレス・数字や記号だけの選択では
/// フローティングアイコンを出さない。
enum SelectionFilter {
    static func isTranslatable(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        // 文字を1つも含まない（数字・記号のみ）は対象外
        guard trimmed.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) }) else {
            return false
        }

        // 空白を含まない1トークンの場合、URL・ドメイン・ファイル名・メールを除外
        if !trimmed.contains(where: \.isWhitespace) {
            if trimmed.contains("://") { return false }
            if trimmed.wholeMatch(of: /(www\.)?[\w\-]+(\.[\w\-]+)+(\/\S*)?/) != nil {
                return false
            }
            if trimmed.wholeMatch(of: /\S+@\S+\.\S+/) != nil {
                return false
            }
        }
        return true
    }
}
