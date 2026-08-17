import Testing
@testable import Kioku

/// chrF。エンジンを比べる物差しなので、値が壊れると比較そのものが嘘になる。
/// 絶対値の妥当性より、**大小関係が期待どおりか**を固定する。
@Suite("chrF")
struct ChrFTests {
    @Test("完全一致は1.0")
    func identical() {
        let s = ChrF.score(hypothesis: "I'll check and get back to you.",
                           reference: "I'll check and get back to you.")
        #expect(abs(s - 1.0) < 1e-9)
    }

    @Test("共通する文字がなければ0")
    func noOverlap() {
        #expect(ChrF.score(hypothesis: "abcdef", reference: "ぎゃくてん") == 0)
    }

    @Test("空文字は0（0除算で落ちない）")
    func emptyInputs() {
        #expect(ChrF.score(hypothesis: "", reference: "確認します") == 0)
        #expect(ChrF.score(hypothesis: "確認します", reference: "") == 0)
        #expect(ChrF.score(hypothesis: "", reference: "") == 0)
    }

    @Test("近い訳のほうが、遠い訳より高い")
    func closerScoresHigher() {
        let reference = "I'll check and get back to you."
        let near = ChrF.score(hypothesis: "I will check and get back to you.",
                              reference: reference)
        let far = ChrF.score(hypothesis: "I will confirm and return.", reference: reference)
        #expect(near > far)
    }

    @Test("日本語でも分かち書きなしで機能する")
    func worksOnJapanese() {
        let reference = "確認して改めてご連絡します。"
        let near = ChrF.score(hypothesis: "確認してご連絡します。", reference: reference)
        let far = ChrF.score(hypothesis: "承知しました。", reference: reference)
        #expect(near > far)
        #expect(near > 0.5)
    }

    @Test("冗長な訳は再現率が満点でも精度で下がる")
    func verbosityIsPenalized() {
        let reference = "確認します。"
        // 参照訳を丸ごと含みつつ、余計な語を足したもの
        let padded = ChrF.score(hypothesis: "確認します。なお念のため申し添えます。",
                                reference: reference)
        let exact = ChrF.score(hypothesis: "確認します。", reference: reference)
        #expect(exact > padded)
    }

    @Test("語順が違うと下がるが、無関係な文よりは高い")
    func wordOrderMatters() {
        let reference = "The build fails on CI but passes locally."
        let reordered = ChrF.score(hypothesis: "The build passes locally but fails on CI.",
                                   reference: reference)
        let unrelated = ChrF.score(hypothesis: "Please migrate to the new endpoint.",
                                   reference: reference)
        #expect(reordered < 1.0)
        #expect(reordered > unrelated)
    }
}
