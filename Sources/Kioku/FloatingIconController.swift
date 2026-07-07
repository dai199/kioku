import AppKit
import SwiftUI

/// テキスト選択直後に出す小さなフローティングアイコン。
/// フォーカスを奪わないパネル（nonactivating）で表示し、クリックで翻訳ポップアップを開く。
@MainActor
final class FloatingIconController {
    var onClick: (() -> Void)?

    private let iconSize: CGFloat = 30
    private var hideTask: Task<Void, Never>?
    private lazy var panel: NSPanel = makePanel()

    func show(near anchor: NSPoint) {
        hideTask?.cancel()
        panel.setFrameOrigin(clamped(NSPoint(x: anchor.x + 6, y: anchor.y + 6)))
        if !panel.isVisible {
            panel.alphaValue = 0
        }
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }
        // 放置されたら自動で消える
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    func hide() {
        hideTask?.cancel()
        panel.orderOut(nil)
    }

    private func clamped(_ origin: NSPoint) -> NSPoint {
        let screen = NSScreen.screens.first { NSMouseInRect(origin, $0.frame, false) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return origin }
        return NSPoint(
            x: min(max(origin.x, frame.minX), frame.maxX - iconSize),
            y: min(max(origin.y, frame.minY), frame.maxY - iconSize)
        )
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: iconSize, height: iconSize),
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
        panel.contentView = NSHostingView(rootView: FloatingIconView { [weak self] in
            self?.onClick?()
        })
        return panel
    }
}

private struct FloatingIconView: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(nsImage: BrandIcon.template)
                .renderingMode(.template)
                .foregroundStyle(.tint)
                .frame(width: 26, height: 26)
                .background(.regularMaterial, in: Circle())
                .overlay(Circle().strokeBorder(.separator, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .padding(2)
    }
}
