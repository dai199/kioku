import Testing
@testable import Kioku

/// 選択テキストのフィルタ。
/// 「翻訳する価値がない選択でフローティングアイコンを出さない」ための番人なので、
/// 通すべきものと弾くべきものを両方向から固定しておく。
@Suite("選択フィルタ")
struct SelectionFilterTests {
    @Test("翻訳対象として通す", arguments: [
        "Hello, world.",
        "これはテストです。",
        "deprecated",                       // ドットのない単語は素通し
        "Visit example.com for details",    // 空白を含む＝文なのでURLが混じっても通す
        "The API is deprecated.",
    ])
    func translatable(text: String) {
        #expect(SelectionFilter.isTranslatable(text))
    }

    @Test("翻訳対象から弾く", arguments: [
        "",
        "   \n  ",
        "12345",                    // 文字を1つも含まない
        "!!!???",
        "3.14",
        "https://example.com/path", // URL
        "example.com",              // ドメイン
        "www.example.co.jp",
        "user@example.com",         // メールアドレス
        "README.md",                // ファイル名
    ])
    func notTranslatable(text: String) {
        #expect(!SelectionFilter.isTranslatable(text))
    }

    @Test("前後の空白は判定に影響しない")
    func ignoresSurroundingWhitespace() {
        #expect(SelectionFilter.isTranslatable("  Hello  "))
        #expect(!SelectionFilter.isTranslatable("\n example.com \t"))
    }
}
