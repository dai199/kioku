import AppKit
import SwiftUI

/// 翻訳結果を表示するポップアップパネル。
/// 前面アプリのフォーカスを奪わないよう nonactivating で表示する
/// （日→英の本文置換で選択状態を維持する必要があるため）。
/// 高さは内容にフィットさせ、上端を固定したまま下方向に伸縮する（HIG: パネルは必要最小限に）。
@MainActor
final class PopupController {
    private let panelWidth: CGFloat = 360
    private let estimatedHeight: CGFloat = 150
    private lazy var panel: NSPanel = makePanel()
    private var currentSession: TranslationSession?

    var isVisible: Bool { panel.isVisible }

    func show(session: TranslationSession, onOpenSettings: @escaping () -> Void) {
        currentSession?.finalize()
        currentSession?.cancel()
        currentSession = session

        let placement = placement(for: session.event)
        panel.setFrame(
            NSRect(
                origin: placement.origin,
                size: NSSize(width: panelWidth, height: estimatedHeight)
            ),
            display: false
        )
        panel.contentView = NSHostingView(rootView: PopupView(
            session: session,
            showArrow: placement.showArrow,
            arrowMidX: placement.arrowMidX,
            onOpenSettings: onOpenSettings,
            onClose: { [weak self] in self?.hide() },
            onSizeChange: { [weak self] size in self?.resizeKeepingTop(to: size) }
        ))
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

    /// 内容サイズの変化に合わせ、上端を固定したままパネルを伸縮する。
    /// 画面からはみ出す場合は見える位置までずらす（下端優先で全体が見えることを保証）。
    private func resizeKeepingTop(to size: CGSize) {
        let frame = panel.frame
        guard abs(frame.height - size.height) > 0.5 || abs(frame.width - size.width) > 0.5 else {
            return
        }
        var newFrame = NSRect(
            x: frame.minX,
            y: frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
        if let visible = (panel.screen ?? NSScreen.main)?.visibleFrame {
            if newFrame.maxY > visible.maxY - 8 {
                newFrame.origin.y = visible.maxY - 8 - newFrame.height
            }
            if newFrame.minY < visible.minY + 8 {
                newFrame.origin.y = visible.minY + 8
            }
        }
        panel.setFrame(newFrame, display: true)
    }

    /// 選択範囲の中央直下に、矢印が選択を指す形で出す。
    /// 下に入らなければ選択の上に反転（その場合は矢印なし）。
    private func placement(for event: SelectionEvent) -> (origin: NSPoint, showArrow: Bool, arrowMidX: CGFloat) {
        let anchor = event.selectionBounds.map { NSPoint(x: $0.midX, y: $0.minY) }
            ?? event.mouseLocation
        var origin = NSPoint(x: anchor.x - panelWidth / 2, y: anchor.y - estimatedHeight - 2)
        var showArrow = true

        let screen = NSScreen.screens.first { NSMouseInRect(anchor, $0.frame, false) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            origin.x = min(max(origin.x, frame.minX + 8), frame.maxX - panelWidth - 8)
            if origin.y < frame.minY + 8 {
                let top = event.selectionBounds?.maxY ?? anchor.y
                origin.y = top + 8
                showArrow = false
            }
        }
        let arrowMidX = min(max(anchor.x - origin.x, 24), panelWidth - 24)
        return (origin, showArrow, arrowMidX)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: estimatedHeight),
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
    let showArrow: Bool
    let arrowMidX: CGFloat
    let onOpenSettings: () -> Void
    let onClose: () -> Void
    let onSizeChange: (CGSize) -> Void

    @State private var isOriginalExpanded = false
    @State private var hasAppeared = false

    /// 手動でテキストを切り詰める。lineLimitによるシステム省略だと
    /// 「…をクリックすると全文がオーバーレイ表示され下の内容にかぶる」
    /// macOS標準動作が発動してしまうため、省略はこちらで制御する。
    private static func clip(_ text: String, maxLines: Int, maxChars: Int) -> (text: String, isClipped: Bool) {
        var clipped = text
        let lines = text.components(separatedBy: "\n")
        if lines.count > maxLines {
            clipped = lines.prefix(maxLines).joined(separator: "\n")
        }
        if clipped.count > maxChars {
            clipped = String(clipped.prefix(maxChars))
        }
        guard clipped != text else { return (text, false) }
        return (clipped + "…", true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            originalSection
            Divider()
            translationSection
        }
        .padding(12)
        .padding(.top, showArrow ? 8 : 0)
        .frame(width: 360)
        // 提案サイズに関わらず内容の自然な高さを取り、その実寸をパネルへ通知する
        .fixedSize(horizontal: false, vertical: true)
        .background(.regularMaterial, in: bubble)
        .overlay(bubble.stroke(.separator, lineWidth: 0.5))
        // 出現モーション: フェード（パネル側）＋わずかなスケール（DESIGN.md）
        .scaleEffect(hasAppeared ? 1 : 0.97, anchor: .top)
        .onAppear {
            withAnimation(.easeOut(duration: 0.18)) {
                hasAppeared = true
            }
        }
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { size in
            onSizeChange(size)
        }
    }

    /// 待ち時間の表示。応答に15秒以上かかることがあり、その間に
    /// 「進んでいるのか固まったのか」が分からないのがいちばん困る。
    /// 数字が増えていれば生きていると分かるので、5秒を過ぎたら経過を出す。
    private func elapsedLabel(prefix: String, font: Font = .callout) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = Int(context.date.timeIntervalSince(session.startedAt))
            Text(elapsed >= 5 ? "\(prefix)… \(elapsed)秒" : "\(prefix)…")
                .font(font)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    /// 「覚える」ボタンのツールチップ。アイコンのみなので、
    /// 何が起きたか（起きるか）はここで伝える。
    private var cardHelp: String {
        switch session.cardState {
        case .notAdded: "この訳を復習カードに追加"
        case .added: "復習カードに追加しました"
        case .alreadyExists: "同じカードが既にあります"
        }
    }

    private var bubble: BubbleShape {
        BubbleShape(arrowMidX: showArrow ? arrowMidX : nil)
    }

    /// 吹き出し形状。上辺の矢印が選択範囲を指す（arrowMidX=nilで矢印なし）。
    private struct BubbleShape: Shape {
        var arrowMidX: CGFloat?
        var arrowHeight: CGFloat = 8
        var arrowWidth: CGFloat = 16
        var cornerRadius: CGFloat = 14

        func path(in rect: CGRect) -> Path {
            guard let arrowMidX else {
                return Path(roundedRect: rect, cornerRadius: cornerRadius)
            }
            let body = CGRect(
                x: rect.minX,
                y: rect.minY + arrowHeight,
                width: rect.width,
                height: rect.height - arrowHeight
            )
            var path = Path(roundedRect: body, cornerRadius: cornerRadius)
            path.move(to: CGPoint(x: arrowMidX - arrowWidth / 2, y: body.minY))
            path.addLine(to: CGPoint(x: arrowMidX, y: rect.minY))
            path.addLine(to: CGPoint(x: arrowMidX + arrowWidth / 2, y: body.minY))
            path.closeSubpath()
            return path
        }
    }

    // メタ情報の階層: 最も控えめに（caption2 / tertiary）
    private var header: some View {
        HStack(spacing: 6) {
            Text(session.event.appName ?? "選択テキスト")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            // バッジクリックで方向を反転して再翻訳（自動判定が外れたとき用）
            Button {
                session.flipDirection()
            } label: {
                HStack(spacing: 3) {
                    DirectionBadge(sourceLang: session.sourceLanguage)
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 7, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .help("翻訳方向を切り替える")
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
    }

    // 原文: 訳文（title3）よりは小さいが、何を翻訳したかが読み取れる大きさに。
    // 長文は手動で切り詰め、シェブロンで展開（ポップアップごと下に伸びる）。
    private var originalSection: some View {
        let collapsed = Self.clip(session.event.text, maxLines: 4, maxChars: 140)
        let expanded = Self.clip(session.event.text, maxLines: 24, maxChars: 1200)
        return HStack(alignment: .top, spacing: 6) {
            if collapsed.isClipped {
                // 省略時は本文クリックで展開/たたむをトグル。
                // onTapGestureはnonactivatingパネルでは最初のクリックが
                // 届かないことがあるため、確実に動くButtonで包む
                Button {
                    isOriginalExpanded.toggle()
                } label: {
                    Text(isOriginalExpanded ? expanded.text : collapsed.text)
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isOriginalExpanded ? "クリックでたたむ" : "クリックで全文表示")
            } else {
                Text(session.event.text)
                    .font(.callout)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if collapsed.isClipped {
                Button {
                    isOriginalExpanded.toggle()
                } label: {
                    Image(systemName: isOriginalExpanded ? "chevron.up" : "chevron.down")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(isOriginalExpanded ? "原文をたたむ" : "原文をすべて表示")
            }
            Button {
                SpeechSpeaker.shared.speak(session.event.text, languageCode: session.sourceLanguage)
            } label: {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.callout)
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
                elapsedLabel(prefix: "翻訳中")
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .center)

        case .streaming(let partial):
            VStack(alignment: .leading, spacing: 6) {
                // 訳文はこのポップアップの主役: title3で最も大きく
                Text(Self.clip(partial, maxLines: 20, maxChars: 1000).text)
                    .font(.title3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    elapsedLabel(prefix: "生成中", font: .caption2)
                    Spacer()
                }
            }

        case .done(let translation):
            VStack(alignment: .leading, spacing: 8) {
                // 読み上げは原文・訳文とも「その文の右」に置く（左右対称）。
                // 下のボタン列は「訳をどうするか」の操作だけに絞る
                HStack(alignment: .top, spacing: 6) {
                    // 訳文はこのポップアップの主役: title3で最も大きく
                    Text(Self.clip(translation, maxLines: 20, maxChars: 1000).text)
                        .font(.title3)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        SpeechSpeaker.shared.speak(
                            translation, languageCode: session.targetLanguage
                        )
                    } label: {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("訳文を読み上げ")
                }
                HStack(spacing: 10) {
                    // 日→英ライティング支援: 選択中の日本語を採用した英文で置き換える
                    if session.sourceLanguage == "ja", TextReplacer.isReplaceable(session.event) {
                        Button {
                            // 置換の成否だけでなく、AX書き込みかペーストかも記録する
                            // （ペーストは反映を確認できないため区別する）
                            if let method = TextReplacer
                                .replace(event: session.event, with: translation)
                                .adoptionMethod {
                                session.recordAdoption(of: translation, via: method)
                                onClose()
                            }
                        } label: {
                            Label("置き換える", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .controlSize(.small)
                        .buttonStyle(.borderedProminent)
                    }
                    // エンジンによっては再生成そのものが成立しない（決定的な出力を返す）。
                    // できない操作を出して黙って無視されるより、出さないほうがよい
                    if session.capabilities.canRegenerate {
                        if session.capabilities.canDirectStyle {
                            // 素の再生成は「なぜ却下したか」が残らない。方向を選べるようにして、
                            // 却下理由を推論せず事実として受け取る（SPEC §11）
                            Menu {
                                ForEach(StyleDirection.allCases, id: \.self) { direction in
                                    Button(direction.label) {
                                        session.regenerate(direction: direction)
                                    }
                                }
                            } label: {
                                Label("別の訳", systemImage: "arrow.clockwise")
                            } primaryAction: {
                                session.regenerate()
                            }
                            .menuStyle(.button)
                            .controlSize(.small)
                            .fixedSize()
                            .help("違う言い回しを提案してもらう（▾で方向を指定）")
                        } else {
                            Button {
                                session.regenerate()
                            } label: {
                                Label("別の訳", systemImage: "arrow.clockwise")
                            }
                            .controlSize(.small)
                            .help("違う言い回しを提案してもらう")
                        }
                    }
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(translation, forType: .string)
                        // コピーも「採用」シグナル（日→英では学習ログにも残る）
                        session.recordAdoption(of: translation, via: .copy)
                    } label: {
                        Label("コピー", systemImage: "doc.on.doc")
                    }
                    .controlSize(.small)
                    // 「覚える」: AI提案を待たずその場でカード化する。
                    // 学習アプリとしての核なので、幅が許すかぎりラベルを出す
                    Button {
                        session.addCard(for: translation)
                    } label: {
                        if session.cardState == .notAdded {
                            Label("覚える", systemImage: "rectangle.stack.badge.plus")
                        } else {
                            Label("追加済み", systemImage: "checkmark")
                        }
                    }
                    .controlSize(.small)
                    .disabled(session.cardState != .notAdded)
                    .help(cardHelp)
                    Spacer()
                }
                // ボタンはテキストのみ（macOS標準のプッシュボタンの作法）。
                // アイコンを添えると1つあたり約18pt太り、4つ並べると幅360ptに収まらない。
                // Labelのまま宣言しておき、スタイルだけここで落とす
                .labelStyle(.titleOnly)
            }

        case .failed(let message, let missingAPIKey):
            VStack(alignment: .leading, spacing: 8) {
                // 対処が書かれた文言もあるので切り詰めない（ポップアップは下に伸びる）。
                // 上限だけは残す（APIの長大なエラー本文でパネルが伸びきらないように）
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(8)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    if missingAPIKey {
                        Button("設定を開く…") {
                            onOpenSettings()
                            onClose()
                        }
                        .controlSize(.small)
                    } else {
                        // タイムアウトや一時的な通信断はやり直せば通ることが多い。
                        // 選択し直しを強いない
                        Button("再試行") { session.retry() }
                            .controlSize(.small)
                            .buttonStyle(.borderedProminent)
                    }
                    Spacer()
                }
            }
        }
    }
}
