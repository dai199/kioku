import Testing
@testable import Kioku

/// カードの表裏の決め方。
/// ポップアップと履歴画面の両方から呼ばれるので、
/// 「どちらから追加しても同じ向きのカードになる」ことをここで担保する。
@Suite("カードの表裏")
struct CardContentTests {
    @Test("日→英: 原文の日本語が表、訳した英文が裏")
    func writingDirection() {
        let content = CardContent.make(
            sourceText: "確認します",
            translatedText: "Let me check.",
            sourceLang: "ja"
        )
        #expect(content.front == "確認します")
        #expect(content.back == "Let me check.")
    }

    @Test("英→日: 訳した日本語が表、原文の英文が裏")
    func readingDirection() {
        let content = CardContent.make(
            sourceText: "Let me check.",
            translatedText: "確認します",
            sourceLang: "en"
        )
        #expect(content.front == "確認します")
        #expect(content.back == "Let me check.")
    }

    @Test("方向が逆でも同じ内容なら同じ表裏になる（重複判定が効く前提）")
    func bothDirectionsAgree() {
        let writing = CardContent.make(
            sourceText: "確認します", translatedText: "Let me check.", sourceLang: "ja"
        )
        let reading = CardContent.make(
            sourceText: "Let me check.", translatedText: "確認します", sourceLang: "en"
        )
        #expect(writing == reading)
    }
}
