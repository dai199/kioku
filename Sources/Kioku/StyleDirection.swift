import Foundation

/// 訳を作り直すときの「どっちに寄せてほしいか」。
///
/// 素の「別の訳」は押された理由が分からない（文体が気に入らないのか、
/// 誤訳なのか）。方向を明示してもらえば理由が事実として残るので、
/// スタイル適応（SPEC §11）の推定を挟まずに済む。
///
/// 軸はフォーマリティと長さの2本に絞っている。SPEC §11の当初案は4軸だったが、
/// トーン・語彙レベルはフォーマリティと強く相関し、推定が分散するだけだった。
enum StyleDirection: String, Sendable, CaseIterable {
    case casual    // フォーマリティ −
    case formal    // フォーマリティ ＋
    case shorter   // 長さ −

    var label: String {
        switch self {
        case .casual: "もっとカジュアルに"
        case .formal: "もっとフォーマルに"
        case .shorter: "もっと短く"
        }
    }

    /// 翻訳プロンプトに足す指示。
    var instruction: String {
        switch self {
        case .casual:
            return "Make this version more casual and conversational than the previous one."
        case .formal:
            return "Make this version more formal and polite than the previous one."
        case .shorter:
            return "Make this version more concise than the previous one. "
                + "Keep the meaning intact but use fewer words."
        }
    }
}
