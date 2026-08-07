import Testing
@testable import Kioku

/// 翻訳キャッシュのキー分離。
/// ここが崩れると「Apple Translationに切り替えたのにGeminiの訳が返る」
/// のような、気づきにくく質の悪い事故になる。
@MainActor
@Suite("翻訳キャッシュ")
struct TranslationCacheTests {
    private let text = "確認します"

    @Test("同じ文・同じ方向・同じ版なら返す")
    func returnsStoredTranslation() {
        let cache = TranslationCache()
        cache.store("Let me check.", text: text, source: "ja", target: "en", version: "gemini/1")
        #expect(
            cache.lookup(text: text, source: "ja", target: "en", version: "gemini/1")
                == "Let me check."
        )
    }

    @Test("エンジン（版）が違えば別のキャッシュ")
    func separatesByVersion() {
        let cache = TranslationCache()
        cache.store("Let me check.", text: text, source: "ja", target: "en", version: "gemini/1")
        #expect(cache.lookup(text: text, source: "ja", target: "en", version: "apple/1") == nil)
        // プロンプト更新でも同じく無効化される
        #expect(cache.lookup(text: text, source: "ja", target: "en", version: "gemini/2") == nil)
    }

    @Test("翻訳方向が違えば別のキャッシュ")
    func separatesByDirection() {
        let cache = TranslationCache()
        cache.store("Let me check.", text: text, source: "ja", target: "en", version: "gemini/1")
        #expect(cache.lookup(text: text, source: "en", target: "ja", version: "gemini/1") == nil)
    }

    @Test("未登録の文はnil")
    func missReturnsNil() {
        let cache = TranslationCache()
        #expect(cache.lookup(text: text, source: "ja", target: "en", version: "gemini/1") == nil)
    }
}
