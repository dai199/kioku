import SwiftUI

// DESIGN.mdのトークンを実装した共通コンポーネント。
// 画面をまたいで同じ見た目が必要なものはここに集約する。

/// 翻訳方向バッジ（メタ層: caption2 / secondary）
struct DirectionBadge: View {
    let sourceLang: String

    var body: some View {
        Text(sourceLang == "ja" ? "日 → 英" : "英 → 日")
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(.quaternary, in: Capsule())
    }
}

/// カード状ボックス（角丸8pt・quaternary背景・パディング10pt）
struct CardBoxModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}

extension View {
    func cardBox() -> some View {
        modifier(CardBoxModifier())
    }
}
