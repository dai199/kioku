import SwiftUI
import Translation

/// 翻訳データをアプリ内でダウンロードさせるボタン。
///
/// `AppleTranslationEngine` はビューを介さずセッションを作るため
/// `canRequestDownloads` が false になり、ダウンロード確認UIを出せない。
/// 一方この `.translationTask` はビューに紐づくので、そこから作られたセッションなら
/// `prepareTranslation()` が確認UIを提示できる。
/// システム設定への往復をなくすために、この経路だけ用意する。
///
/// 型 `TranslationSession.Configuration`（Appleのフレームワーク側）がmacOS 26.4以降なので、
/// ビューごと切り出して可用性で包んでいる（設定画面全体は26.0のまま動く）。
enum LanguageDownloadPhase: Equatable, Sendable {
    case idle
    case downloading
    case done
    case failed(String)
}

/// ダウンロードの状態だけを持つ入れ物。
///
/// `.translationTask` の閉包はビューの文脈からメインアクター隔離と推論されるが、
/// `prepareTranslation()` は非分離なので、そこへ非Sendableな session を渡す形になり
/// Swift 6の並行性検査に引っかかる。閉包を `@Sendable`（＝非分離）にすればよいが、
/// するとビュー自身（`@State` を含む）を捕捉できない。
/// そこで**メインアクター隔離クラス＝暗黙にSendable**なこの型だけを捕捉し、
/// 結果を書き戻す。
@MainActor
final class LanguageDownloadModel: ObservableObject {
    @Published var phase: LanguageDownloadPhase = .idle
}

@available(macOS 26.4, *)
struct LanguageDownloadButton: View {
    let source: String
    let target: String
    /// ダウンロードできなかったときの逃げ道（システム設定へ誘導する）
    let onFallback: () -> Void

    @State private var configuration: TranslationSession.Configuration?
    @StateObject private var model = LanguageDownloadModel()

    private var phase: LanguageDownloadPhase { model.phase }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch phase {
            case .idle, .failed:
                Button("翻訳データをダウンロード…") { startDownload() }
                    .controlSize(.small)
            case .downloading:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("ダウンロード中…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            case .done:
                Label("ダウンロードしました。もう一度お試しください。", systemImage: "checkmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.green)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if case .failed(let message) = phase {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                Button("「言語と地域」を開く…", action: onFallback)
                    .controlSize(.small)
            }
        }
        // configuration が nil から値に変わるとactionが走る。
        // @Sendable を付けて閉包を非分離にする（そうしないと session が
        // メインアクター隔離になり、非分離な prepareTranslation() へ渡せない）。
        // 捕捉するのはSendableなmodelだけで、ビュー自身は捕捉しない
        .translationTask(configuration) { @Sendable [model] session in
            let result: LanguageDownloadPhase
            do {
                try await session.prepareTranslation()
                result = .done
            } catch {
                result = .failed(error.localizedDescription)
            }
            await MainActor.run { model.phase = result }
        }
    }

    private func startDownload() {
        model.phase = .downloading
        // 同じ値を入れ直しても再実行されないので、一度nilに戻してから設定する
        configuration = nil
        configuration = TranslationSession.Configuration(
            source: Locale.Language(identifier: source),
            target: Locale.Language(identifier: target)
        )
    }
}
