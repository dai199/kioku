import AppKit
import ApplicationServices

struct SelectionEvent {
    let text: String
    let appName: String?
    let bundleID: String?
    /// 選択元アプリのプロセスID（ペーストシミュレートの送信先）
    let pid: pid_t?
    /// 選択を保持しているAX要素（本文置換の書き込み先）
    let element: AXUIElement?
    /// 選択範囲のスクリーン座標（AppKit座標系）。取れないアプリではnil。
    let selectionBounds: NSRect?
    let mouseLocation: NSPoint
    /// マウスドラッグ選択の開始点。AXで座標が取れないアプリで
    /// 「選択範囲の右上」を推定するために使う（キーボード選択ではnil）。
    let mouseDownLocation: NSPoint?
    /// 出典: フォーカスウィンドウのタイトル
    let windowTitle: String?
    /// 出典: ドキュメントのURL/パス（公開しているアプリのみ）
    let documentURL: String?

    /// アイコンの位置をどこから決めたか（実測用。近似に落ちる頻度を見る）
    enum AnchorSource: String {
        case selectionBounds   // AXが選択範囲を返した。狙いどおりの位置
        case dragRect          // AXが返さないアプリ。ドラッグ2点からの近似
        case fallback          // キーボード選択で範囲も取れない。手がかりなし
    }

    /// フローティングアイコンを出すべき位置。**常に選択範囲の右上**。
    ///
    /// AXが選択範囲を返すアプリなら、マウス・キーボードのどちらで選んでも
    /// 同じ規則で決まる（入力方法には依存しない）。
    /// 返さないアプリでは、マウス選択に限りドラッグ2点から近似する。
    /// キーボード選択で範囲も取れない場合だけは手がかりがないので、
    /// やむなくマウス位置に落とす（`fallback`。頻度はログで測っている）。
    var anchor: (point: NSPoint, source: AnchorSource) {
        if let bounds = selectionBounds {
            return (NSPoint(x: bounds.maxX, y: bounds.maxY), .selectionBounds)
        }
        if let down = mouseDownLocation {
            return (
                NSPoint(x: max(down.x, mouseLocation.x), y: max(down.y, mouseLocation.y)),
                .dragRect
            )
        }
        return (mouseLocation, .fallback)
    }

    var iconAnchor: NSPoint { anchor.point }
}

extension SelectionEvent {
    /// Probeの結果から翻訳対象のイベントを作る。翻訳対象外の選択ならnil。
    @MainActor
    init?(probe: SelectionProbe.Probe, mouseDownLocation: NSPoint? = nil) {
        guard let text = probe.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty,
              probe.bundleID != Bundle.main.bundleIdentifier,
              SelectionFilter.isTranslatable(text)
        else { return nil }
        self.init(
            text: text,
            appName: probe.appName,
            bundleID: probe.bundleID,
            pid: probe.pid,
            element: probe.element,
            selectionBounds: probe.selectionBounds,
            mouseLocation: NSEvent.mouseLocation,
            mouseDownLocation: mouseDownLocation,
            windowTitle: probe.windowTitle,
            documentURL: probe.documentURL
        )
    }
}

/// グローバルなマウスイベントを監視し、他アプリでのテキスト選択を検知する。
/// 選択ジェスチャ（ドラッグ・ダブルクリック）の終わり = leftMouseUp の直後に
/// Accessibility APIで選択テキストを読みに行く。
/// グローバルモニタは自アプリ内のイベントには発火しないため、
/// フローティングアイコンやポップアップの操作はここに影響しない。
@MainActor
final class SelectionMonitor {
    var onSelection: ((SelectionEvent) -> Void)?
    /// 新しいクリック・スクロールの開始。表示中のアイコン/ポップアップを隠す合図。
    var onInteractionStarted: (() -> Void)?

    private var monitors: [Any] = []
    private var probeTask: Task<Void, Never>?
    private var lastMouseDownLocation: NSPoint?

    var isRunning: Bool { !monitors.isEmpty }

    func start() {
        guard monitors.isEmpty else { return }
        if let up = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp, handler: { [weak self] _ in
            Task { @MainActor in self?.scheduleProbe(fromMouse: true) }
        }) {
            monitors.append(up)
        }
        if let down = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .scrollWheel],
            handler: { [weak self] event in
                let isLeftDown = event.type == .leftMouseDown
                let location = NSEvent.mouseLocation
                Task { @MainActor in
                    if isLeftDown {
                        self?.lastMouseDownLocation = location
                    }
                    self?.probeTask?.cancel()
                    self?.onInteractionStarted?()
                }
            }
        ) {
            monitors.append(down)
        }
        // キーボード選択（Shift+矢印、⌘Aなど）: 選択キーを離したタイミングで読みに行く
        if let keyUp = NSEvent.addGlobalMonitorForEvents(matching: .keyUp, handler: { [weak self] event in
            let keyCode = event.keyCode
            let flags = event.modifierFlags
            Task { @MainActor in
                guard let self, Self.isSelectionGesture(keyCode: keyCode, flags: flags) else { return }
                self.scheduleProbe(fromMouse: false)
            }
        }) {
            monitors.append(keyUp)
        }
        // 通常のタイピングが始まったら表示中のUIを隠す（mouseDownと同じ扱い）
        if let keyDown = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            let keyCode = event.keyCode
            let flags = event.modifierFlags
            Task { @MainActor in
                guard let self, !Self.isSelectionGesture(keyCode: keyCode, flags: flags) else { return }
                self.probeTask?.cancel()
                self.onInteractionStarted?()
            }
        }) {
            monitors.append(keyDown)
        }
    }

    /// テキスト選択を広げる/作るキー操作か。
    /// Shift+矢印・Shift+Home/End/PageUp/PageDown・⌘A（全選択）を対象とする。
    private static func isSelectionGesture(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> Bool {
        let arrowKeys: Set<UInt16> = [123, 124, 125, 126]
        let navigationKeys: Set<UInt16> = [115, 116, 119, 121] // Home, PageUp, End, PageDown
        if flags.contains(.shift), arrowKeys.contains(keyCode) || navigationKeys.contains(keyCode) {
            return true
        }
        if flags.contains(.command), keyCode == 0 { // ⌘A
            return true
        }
        return false
    }

    func stop() {
        probeTask?.cancel()
        for monitor in monitors {
            NSEvent.removeMonitor(monitor)
        }
        monitors.removeAll()
    }

    private func scheduleProbe(fromMouse: Bool) {
        probeTask?.cancel()
        probeTask = Task { @MainActor [weak self] in
            // 選択状態がAXツリーに反映されるまで少し待つ
            try? await Task.sleep(for: .milliseconds(120))
            guard let self, !Task.isCancelled else { return }

            guard let event = SelectionEvent(
                probe: SelectionProbe.readCurrentSelection(),
                mouseDownLocation: fromMouse ? self.lastMouseDownLocation : nil
            ) else { return }
            self.onSelection?(event)
        }
    }
}
