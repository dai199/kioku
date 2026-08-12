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
                windowTitle: window.title, documentURL: window.url
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
                windowTitle: window.title, documentURL: window.url
            )
        }
        return Probe(
            text: text, appName: appName, bundleID: bundleID, pid: pid,
            element: element,
            selectionBounds: selectionBounds(of: element, appName: appName),
            windowTitle: window.title, documentURL: window.url
        )
    }

    /// 選択矩形が取れなかった理由。段階ごとに打ち手が変わるので分けて記録する。
    private enum BoundsFailure: String {
        case noSelectedRange     // 選択範囲そのものが取れない
        case boundsUnsupported   // kAXBoundsForRange に非対応（そもそも属性が無い）
        case boundsFailed        // 属性はあるが取得に失敗
        case degenerateRect      // 取れたが大きさがない
        case noScreen
    }

    /// 代替案の可否を測る: 要素全体の矩形が取れるか。
    /// 選択範囲が取れないアプリでも、これが取れれば
    /// 「テキストのある領域」には基づいた位置を出せる。
    /// AXFrameは定数が提供されていないので、position と size から組み立てる。
    private static func elementFrame(of element: AXUIElement) -> CGRect? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, kAXPositionAttribute as CFString, &positionRef
        ) == .success,
            AXUIElementCopyAttributeValue(
                element, kAXSizeAttribute as CFString, &sizeRef
            ) == .success,
            let positionRef, let sizeRef,
            CFGetTypeID(positionRef) == AXValueGetTypeID(),
            CFGetTypeID(sizeRef) == AXValueGetTypeID()
        else { return nil }

        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(unsafeDowncast(positionRef, to: AXValue.self), .cgPoint, &origin),
              AXValueGetValue(unsafeDowncast(sizeRef, to: AXValue.self), .cgSize, &size)
        else { return nil }
        return CGRect(origin: origin, size: size)
    }

    private static func logBoundsFailure(
        _ reason: BoundsFailure, appName: String?, element: AXUIElement,
        axError: AXError? = nil, rect: CGRect? = nil
    ) {
        let frame = elementFrame(of: element)
        let frameText = frame.map {
            "\(Int($0.origin.x)),\(Int($0.origin.y)) \(Int($0.width))x\(Int($0.height))"
        } ?? "なし"
        // サイズが0でも原点が正しければアイコンの位置には使える。値を見て判断する
        let rectText = rect.map {
            "\(Int($0.origin.x)),\(Int($0.origin.y)) \(Int($0.width))x\(Int($0.height))"
        } ?? "-"
        translationLogger.debug(
            """
            選択矩形が取れない app=\(appName ?? "?", privacy: .public) \
            理由=\(reason.rawValue, privacy: .public) \
            AXError=\(axError.map { String($0.rawValue) } ?? "-", privacy: .public) \
            返り値=\(rectText, privacy: .public) \
            代替(要素の矩形)=\(frameText, privacy: .public)
            """
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

    /// 指定した範囲の矩形を問い合わせる。大きさのない矩形は情報がないものとして捨てる
    /// （成功を返しつつ固定値を寄越すアプリがあるため）。
    private static func boundsForRange(element: AXUIElement, range: AXValue) -> CGRect? {
        var boundsRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element, kAXBoundsForRangeParameterizedAttribute as CFString, range, &boundsRef
        ) == .success,
            let boundsRef, CFGetTypeID(boundsRef) == AXValueGetTypeID()
        else { return nil }

        var rect = CGRect.zero
        guard AXValueGetValue(unsafeDowncast(boundsRef, to: AXValue.self), .cgRect, &rect),
              rect.width > 0 || rect.height > 0
        else { return nil }
        return rect
    }

    /// 選択範囲のスクリーン上の矩形を取得し、AX座標（左上原点）からAppKit座標（左下原点）へ変換する。
    /// 取れなかった場合は、どの段階で落ちたかをログに残す（アプリごとに事情が違うため）。
    private static func selectionBounds(of element: AXUIElement, appName: String?) -> NSRect? {
        var rangeRef: CFTypeRef?
        let rangeError = AXUIElementCopyAttributeValue(
            element, kAXSelectedTextRangeAttribute as CFString, &rangeRef
        )
        guard rangeError == .success,
              let rangeRef, CFGetTypeID(rangeRef) == AXValueGetTypeID()
        else {
            logBoundsFailure(.noSelectedRange, appName: appName, element: element,
                             axError: rangeError)
            return nil
        }
        let rangeValue = unsafeDowncast(rangeRef, to: AXValue.self)

        // 属性そのものに対応しているかを先に見る。非対応なら手当ての方向が変わる
        var parameterizedNames: CFArray?
        AXUIElementCopyParameterizedAttributeNames(element, &parameterizedNames)
        let supportsBounds = (parameterizedNames as? [String])?
            .contains(kAXBoundsForRangeParameterizedAttribute as String) ?? false
        guard supportsBounds else {
            logBoundsFailure(.boundsUnsupported, appName: appName, element: element)
            return nil
        }

        // 選択範囲全体で問い合わせる。Chrome/Slackはここで成功を返しつつ
        // 中身が固定値（0,956 0x0）というスタブ実装だった（実測）
        var rect = boundsForRange(element: element, range: rangeValue)

        // 全体で駄目でも「先頭の1文字」なら返すアプリがあるので試す。
        // 文字単位でだけ実装されている場合を拾うため
        if rect == nil {
            var selected = CFRange()
            if AXValueGetValue(rangeValue, .cfRange, &selected) {
                var single = CFRange(location: selected.location, length: 1)
                if let singleValue = AXValueCreate(.cfRange, &single) {
                    rect = boundsForRange(element: element, range: singleValue)
                    if rect != nil {
                        translationLogger.debug(
                            "選択矩形を1文字分で取得 app=\(appName ?? "?", privacy: .public)"
                        )
                    }
                }
            }
        }

        guard let rect else {
            logBoundsFailure(.degenerateRect, appName: appName, element: element)
            return nil
        }

        guard let primary = NSScreen.screens.first else {
            logBoundsFailure(.noScreen, appName: appName, element: element)
            return nil
        }
        return NSRect(
            x: rect.origin.x,
            y: primary.frame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }
}
