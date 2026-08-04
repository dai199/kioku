import Foundation
import Testing
@testable import Kioku

/// 週次分析の応答パース。
/// モデルの出力形式は揺れる（コードフェンスで囲む/囲まない）ので、
/// どちらでも落ちないことを固定する。
@Suite("週次分析のJSON抽出")
struct WeeklyAnalyzerTests {
    private func extracted(_ raw: String) -> String? {
        String(data: WeeklyAnalyzer.extractJSONData(raw), encoding: .utf8)
    }

    @Test("素のJSONはそのまま通す")
    func passesPlainJSON() {
        #expect(extracted(#"{"summary":"ok"}"#) == #"{"summary":"ok"}"#)
    }

    @Test("前後の空白・改行を落とす")
    func trimsSurroundingWhitespace() {
        #expect(extracted("\n  {\"summary\":\"ok\"}  \n") == #"{"summary":"ok"}"#)
    }

    @Test("Markdownのコードフェンスを剥がす", arguments: ["```json", "```"])
    func stripsCodeFence(opening: String) {
        let raw = """
        \(opening)
        {"summary":"ok"}
        ```
        """
        #expect(extracted(raw) == #"{"summary":"ok"}"#)
    }

    @Test("複数行のJSONでもフェンスだけを剥がす")
    func keepsInnerNewlines() {
        let raw = """
        ```json
        {
          "summary": "ok"
        }
        ```
        """
        #expect(extracted(raw) == "{\n  \"summary\": \"ok\"\n}")
    }

    @Test("フェンス付きの応答をWeeklyAnalysisとして解釈できる")
    func decodesFencedResponse() throws {
        let raw = """
        ```json
        {
          "summary": "今週は冠詞の選択でつまずく場面が目立ちました。",
          "patterns": [
            {
              "title": "冠詞の脱落",
              "description": "可算名詞の単数形に a / the が付かない",
              "examples": ["I have pen"]
            }
          ],
          "cards": [
            {
              "front": "確認します",
              "back": "Let me check.",
              "reason": "業務で頻出",
              "logId": 12
            }
          ]
        }
        ```
        """
        let analysis = try JSONDecoder().decode(
            WeeklyAnalysis.self, from: WeeklyAnalyzer.extractJSONData(raw)
        )
        #expect(analysis.patterns.count == 1)
        #expect(analysis.patterns.first?.examples == ["I have pen"])
        #expect(analysis.cards.first?.back == "Let me check.")
        #expect(analysis.cards.first?.logId == 12)
    }

    @Test("examples と logId は省略されていても解釈できる")
    func decodesWithOptionalFieldsOmitted() throws {
        let raw = #"""
        {
          "summary": "ok",
          "patterns": [{"title": "冠詞", "description": "説明"}],
          "cards": [{"front": "確認します", "back": "Let me check."}]
        }
        """#
        let analysis = try JSONDecoder().decode(
            WeeklyAnalysis.self, from: WeeklyAnalyzer.extractJSONData(raw)
        )
        #expect(analysis.patterns.first?.examples == nil)
        #expect(analysis.cards.first?.logId == nil)
        #expect(analysis.cards.first?.reason == nil)
    }
}
