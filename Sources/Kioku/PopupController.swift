import AppKit
import SwiftUI

/// 翻訳結果を表示するポップアップパネル。
/// 前面アプリのフォーカスを奪わないよう nonactivating で表示する
/// （日→英の本文置換で選択状態を維持する必要があるため）。
@MainActor
final class PopupController {
    private let size = NSSize(width: 380, height: 240)
    private lazy var panel: NSPanel = makePanel()
    private var currentSession: TranslationSession?

    var isVisible: Bool { panel.isVisible }

    func show(session: TranslationSession, onOpenSettings: @escaping () -> Void) {
        currentSession?.finalize()
        currentSession?.cancel()
        currentSession = session
        panel.contentView = NSHostingView(rootView: PopupView(
            session: session,
            onOpenSettings: onOpenSettings,
            onClose: { [weak self] in self?.hide() }
        ))
        panel.setFrameOrigin(origin(for: session.event))
        if !panel.isVisible {
            panel.alphaValue = 0
        }
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 1
        }
        session.start()
    }

    func hide() {
        currentSession?.finalize()
        currentSession?.cancel()
        currentSession = nil
        panel.orderOut(nil)
    }

    /// 選択範囲の直下（入らなければ上、位置不明ならマウス位置基準）に出す。
    private func origin(for event: SelectionEvent) -> NSPoint {
        let anchor = event.selectionBounds.map { NSPoint(x: $0.minX, y: $0.minY) }
            ?? event.mouseLocation
        var origin = NSPoint(x: anchor.x, y: anchor.y - size.height - 8)

        let screen = NSScreen.screens.first { NSMouseInRect(anchor, $0.frame, false) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            origin.x = min(max(origin.x, frame.minX + 8), frame.maxX - size.width - 8)
            if origin.y < frame.minY + 8 {
                let top = event.selectionBounds?.maxY ?? anchor.y
                origin.y = top + 8
            }
        }
        return origin
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        // 表示した時点のスペース（デスクトップ）に留まる。スペースをまたいで付いてこない
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        return panel
    }
}

struct PopupView: View {
    @ObservedObject var session: TranslationSession
    let onOpenSettings: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            originalSection
            Divider()
            translationSection
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(width: 380, height: 240, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator, lineWidth: 0.5))
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(session.event.appName ?? "選択テキスト")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(session.sourceLanguage == "ja" ? "日 → 英" : "英 → 日")
                .font(.caption2.weight(.medium))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(.quaternary, in: Capsule())
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private var originalSection: some View {
        HStack(alignment: .top, spacing: 6) {
            ScrollView {
                Text(session.event.text)
                    .font(.callout)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 64)
            Button {
                SpeechSpeaker.shared.speak(session.event.text, languageCode: session.sourceLanguage)
            } label: {
                Image(systemName: "speaker.wave.2.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("原文を読み上げ")
        }
    }

    @ViewBuilder
    private var translationSection: some View {
        switch session.phase {
        case .loading:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("翻訳中…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

        case .streaming(let partial):
            VStack(alignment: .leading, spacing: 6) {
                ScrollView {
                    Text(partial)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("生成中…")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
            }

        case .done(let translation):
            VStack(alignment: .leading, spacing: 6) {
                ScrollView {
                    Text(translation)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack(spacing: 10) {
                    // 日→英ライティング支援: 選択中の日本語を採用した英文で置き換える
                    if session.sourceLanguage == "ja", TextReplacer.isReplaceable(session.event) {
                        Button {
                            if TextReplacer.replace(event: session.event, with: translation) {
                                session.recordAdoption(of: translation, via: .replace)
                                onClose()
                            }
                        } label: {
                            Label("置き換える", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .controlSize(.small)
                        .buttonStyle(.borderedProminent)
                    }
                    Button {
                        session.regenerate()
                    } label: {
                        Label("別の訳", systemImage: "arrow.clockwise")
                    }
                    .controlSize(.small)
                    .help("違う言い回しを提案してもらう")
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(translation, forType: .string)
                        // コピーも「採用」シグナル（日→英では学習ログにも残る）
                        session.recordAdoption(of: translation, via: .copy)
                    } label: {
                        Label("コピー", systemImage: "doc.on.doc")
                    }
                    .controlSize(.small)
                    Button {
                        SpeechSpeaker.shared.speak(translation, languageCode: session.targetLanguage)
                    } label: {
                        Image(systemName: "speaker.wave.2.fill")
                    }
                    .controlSize(.small)
                    .help("訳文を読み上げ")
                    Spacer()
                }
            }

        case .failed(let message, let missingAPIKey):
            VStack(alignment: .leading, spacing: 8) {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                if missingAPIKey {
                    Button("設定を開く…") {
                        onOpenSettings()
                        onClose()
                    }
                    .controlSize(.small)
                }
            }
        }
    }
}
