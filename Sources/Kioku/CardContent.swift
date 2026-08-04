import Foundation

/// 翻訳ペアからSRSカードの表裏を決める。
/// 翻訳方向によらず「表=日本語（言いたいこと）・裏=英文」に揃える
/// （SPEC §3.5: 表 日本語 / 裏 採用英文）。復習は日本語を見て英文を思い出す形に統一する。
enum CardContent {
    static func make(
        sourceText: String,
        translatedText: String,
        sourceLang: String
    ) -> (front: String, back: String) {
        sourceLang == "ja"
            ? (front: sourceText, back: translatedText)      // 日→英: 原文が日本語
            : (front: translatedText, back: sourceText)      // 英→日: 訳文が日本語
    }
}
