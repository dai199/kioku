import Foundation
import NaturalLanguage

struct TranslationRequest: Sendable {
    let text: String
    /// ISO言語コード（"en" / "ja"）。SPECどおり言語ペアは最初から抽象化しておく。
    let sourceLanguage: String
    let targetLanguage: String
    /// 「別の訳」再生成時、既に提示した訳（これらとは違う訳を返してもらう）
    var alternativesToAvoid: [String] = []
    /// 「もっとカジュアルに」のような方向指定（指定なしの再生成ではnil）
    var styleDirection: StyleDirection?
}

/// エンジンが応えられる操作。
///
/// エンジンによって能力は決定的に違う。Apple Translationはプロンプトを
/// 受け取る口がないので方向指定を解釈できず、出力も決定的なので
/// 「別の訳」も成立しない。**できない操作をUIに出して黙って無視されるのが最悪**なので、
/// 画面はこれを見てボタンを出し分ける。
struct EngineCapabilities: Sendable {
    /// 「別の訳」で違う候補を出せるか（決定的なエンジンは不可）
    var canRegenerate: Bool
    /// 「もっとカジュアルに」等の方向指定を解釈できるか
    var canDirectStyle: Bool
    /// 文法・ニュアンスの解説を生成できるか
    var canExplain: Bool

    /// プロンプトを自由に組み立てられるLLM向け
    static let full = EngineCapabilities(
        canRegenerate: true, canDirectStyle: true, canExplain: true
    )
    /// 原文を渡して訳を受け取るだけのエンジン向け
    static let translateOnly = EngineCapabilities(
        canRegenerate: false, canDirectStyle: false, canExplain: false
    )
}

/// 訳の背景を解説してもらうための入力。
struct ExplanationRequest: Sendable {
    let sourceText: String
    let translatedText: String
    let sourceLanguage: String
    let targetLanguage: String
}

enum EngineError: LocalizedError {
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case .unsupported(let what):
            return "このエンジンは\(what)に対応していません。"
        }
    }
}

/// 翻訳エンジンの抽象化。将来Apple Translation（オフライン）や
/// オンデバイスLLMへ差し替え・併用できるようにしておく。
protocol TranslationEngine: Sendable {
    /// エンジンと生成条件を一意に表す識別子。翻訳キャッシュのキーと、
    /// 選好シグナル（`translationSession.promptVersion`）の記録に使う。
    ///
    /// **エンジンをまたいで衝突しないこと**（例: `gemini/2026-08-05.1`、`apple/1`）。
    /// 衝突すると、エンジンを切り替えても前のエンジンの訳がキャッシュから返る。
    /// プロンプトを持つエンジンはプロンプトを変えたら必ず上げる
    /// （どの変更が品質に効いたかを後から追うため）。
    var promptVersion: String { get }

    /// 応えられる操作。既定値は置かない — 新しいエンジンを足すとき、
    /// 何ができて何ができないかを必ず考えさせるため
    var capabilities: EngineCapabilities { get }

    func translate(_ request: TranslationRequest) async throws -> String
    /// 逐次テキスト片を返すストリーミング翻訳。
    func translateStream(_ request: TranslationRequest) -> AsyncThrowingStream<String, Error>
    /// 文法・ニュアンスの解説。`capabilities.canExplain` が真のエンジンだけが実装する。
    func explain(_ request: ExplanationRequest) async throws -> String
}

extension TranslationEngine {
    /// 解説できないエンジンの既定。UIは `canExplain` を見て出し分けるので
    /// 通常ここには来ないが、能力の申告と実装がずれたときに黙って通さない。
    func explain(_ request: ExplanationRequest) async throws -> String {
        throw EngineError.unsupported("解説の生成")
    }

    /// ストリーミング未対応エンジンは全文を1回で返す。
    func translateStream(_ request: TranslationRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let engine = self
            Task {
                do {
                    continuation.yield(try await engine.translate(request))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

enum LanguageDetector {
    /// 選択テキストの言語から翻訳方向を決める。
    /// 日本語なら日→英（ライティング支援）、それ以外は英→日（読解支援）とみなす。
    static func direction(for text: String) -> (source: String, target: String) {
        // ひらがな・カタカナが1文字でもあれば日本語とみなす。
        // 英語の用語が多く混ざった日本語文で、NLの判定が英語に倒れるのを防ぐ
        let containsKana = text.unicodeScalars.contains { (0x3040...0x30FF).contains($0.value) }
        if containsKana {
            return ("ja", "en")
        }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(String(text.prefix(200)))
        if recognizer.dominantLanguage == .japanese {
            return ("ja", "en")
        }
        return ("en", "ja")
    }
}
