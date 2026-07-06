import AppKit
import ApplicationServices

/// Accessibility APIで「今フォーカスされているUI要素の選択テキスト」と
/// その画面上の位置を読み取る。
@MainActor
enum SelectionProbe {
    struct Probe {
        let text: String?
        let appName: String?
        let bundleID: String?
        /// 選択元アプリのプロセスID（ペーストシミュレートの送信先）
        let pid: pid_t?
        /// 選択を保持しているAX要素（本文置換の書き込み先）
        let element: AXUIElement?
        /// 選択範囲のスクリーン座標（AppKit座標系・左下原点）。取れないアプリもある。
        let selectionBounds: NSRect?
        /// 出典: フォーカスウィンドウのタイトル
        let windowTitle: String?
        /// 出典: ドキュメントのURL/パス（公開しているアプリのみ）
        let documentURL: String?
        let detail: String
    }

    static func readCurrentSelection() -> Probe {
        let front = NSWorkspace.shared.frontmostApplication
        let appName = front?.localizedName
        let bundleID = front?.bundleIdentifier
        let pid = front?.processIdentifier
        let window = windowInfo(pid: pid)

        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        let focusedError = AXUIElementCopyAttributeValue(
            systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef
        )
        guard focusedError == .success,
              let focusedRef,
              CFGetTypeID(focusedRef) == AXUIElementGetTypeID()
        else {
            return Probe(
                text: nil, appName: appName, bundleID: bundleID, pid: pid,
                element: nil, selectionBounds: nil,
                windowTitle: window.title, documentURL: window.url,
                detail: "フォーカス中のUI要素を取得できませんでした (AXError: \(focusedError.rawValue))"
            )
        }
        let element = unsafeDowncast(focusedRef, to: AXUIElement.self)

        var selectedRef: CFTypeRef?
        let selectedError = AXUIElementCopyAttributeValue(
            element, kAXSelectedTextAttribute as CFString, &selectedRef
        )
        guard selectedError == .success, let text = selectedRef as? String, !text.isEmpty else {
            return Probe(
                text: nil, appName: appName, bundleID: bundleID, pid: pid,
                element: element, selectionBounds: nil,
                windowTitle: window.title, documentURL: window.url,
                detail: "選択テキストがありません (AXError: \(selectedError.rawValue))"
            )
        }
        return Probe(
            text: text, appName: appName, bundleID: bundleID, pid: pid,
            element: element,
            selectionBounds: selectionBounds(of: element),
            windowTitle: window.title, documentURL: window.url,
            detail: "取得成功"
        )
    }

    /// 出典情報: フォーカスウィンドウのタイトルと、公開されていればドキュメントURL/パス。
    /// ブラウザのページURL取得はAXでは安定しないため、フェーズ2で改善予定。
    private static func windowInfo(pid: pid_t?) -> (title: String?, url: String?) {
        guard let pid else { return (nil, nil) }
        let appElement = AXUIElementCreateApplication(pid)

        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appElement, kAXFocusedWindowAttribute as CFString, &windowRef
        ) == .success,
            let windowRef, CFGetTypeID(windowRef) == AXUIElementGetTypeID()
        else { return (nil, nil) }
        let window = unsafeDowncast(windowRef, to: AXUIElement.self)

        var titleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)

        var documentRef: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXDocumentAttribute as CFString, &documentRef)

        return (titleRef as? String, documentRef as? String)
    }

    /// 選択範囲のスクリーン上の矩形を取得し、AX座標（左上原点）からAppKit座標（左下原点）へ変換する。
    private static func selectionBounds(of element: AXUIElement) -> NSRect? {
        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, kAXSelectedTextRangeAttribute as CFString, &rangeRef
        ) == .success,
            let rangeRef, CFGetTypeID(rangeRef) == AXValueGetTypeID()
        else { return nil }
        let rangeValue = unsafeDowncast(rangeRef, to: AXValue.self)

        var boundsRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element, kAXBoundsForRangeParameterizedAttribute as CFString, rangeValue, &boundsRef
        ) == .success,
            let boundsRef, CFGetTypeID(boundsRef) == AXValueGetTypeID()
        else { return nil }

        var rect = CGRect.zero
        guard AXValueGetValue(unsafeDowncast(boundsRef, to: AXValue.self), .cgRect, &rect),
              rect.width > 0 || rect.height > 0
        else { return nil }

        guard let primary = NSScreen.screens.first else { return nil }
        return NSRect(
            x: rect.origin.x,
            y: primary.frame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }
}
