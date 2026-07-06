import AppKit
import ApplicationServices
import os

/// 選択テキストを訳文で置き換える。SPECどおり二段構え：
/// 1. Accessibility APIの書き込み（対応アプリ）— 書き込み後に本当に反映されたか検証する
///    （Chromeなどは「書き込み可能」と申告しつつ反映しないことがある）
/// 2. ペーストシミュレート（⌘V相当をCGEventでHIDタップに送信、クリップボードは復元）
///    pid宛（postToPid）はChrome/Electron系に無視されるためHIDタップ宛にする。
/// どちらも見込めない読取専用領域では isReplaceable が false になり、
/// 呼び出し側はコピーボタンのみを出す。
@MainActor
enum TextReplacer {
    private static let logger = Logger(
        subsystem: "com.daikitagami.kioku", category: "replace"
    )

    /// 置換ボタンを出すべきかの判定。
    static func isReplaceable(_ event: SelectionEvent) -> Bool {
        guard let element = event.element else { return false }
        return isSettable(element, kAXSelectedTextAttribute)
            || isSettable(element, kAXValueAttribute)
    }

    /// 置換を実行する。成功したらtrue。
    static func replace(event: SelectionEvent, with text: String) -> Bool {
        if let element = event.element {
            let selectedTextSettable = isSettable(element, kAXSelectedTextAttribute)
            logger.log("置換開始 app=\(event.appName ?? "?", privacy: .public) AXSelectedText書込可=\(selectedTextSettable)")

            if selectedTextSettable {
                let result = AXUIElementSetAttributeValue(
                    element, kAXSelectedTextAttribute as CFString, text as CFString
                )
                logger.log("AX書き込み結果=\(result.rawValue)")
                if result == .success, verifyReplacement(element: element, original: event.text) {
                    logger.log("AX書き込みで置換成功")
                    return true
                }
                logger.log("AX書き込みが反映されていない（サイレント失敗）→ ペーストへフォールバック")
            }
        } else {
            logger.log("AX要素なし → ペーストへフォールバック")
        }
        return pasteReplace(text: text, targetPID: event.pid)
    }

    /// 書き込み後も選択テキストが元の文のままなら、反映されなかったとみなす。
    /// （成功時は選択が置換文になるか、選択が解除されて空になる）
    private static func verifyReplacement(element: AXUIElement, original: String) -> Bool {
        var selectedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, kAXSelectedTextAttribute as CFString, &selectedRef
        ) == .success,
            let selected = selectedRef as? String
        else { return true } // 読み返せない場合は成功扱い
        return selected != original
    }

    private static func isSettable(_ element: AXUIElement, _ attribute: String) -> Bool {
        var settable = DarwinBoolean(false)
        let error = AXUIElementIsAttributeSettable(element, attribute as CFString, &settable)
        return error == .success && settable.boolValue
    }

    /// クリップボード経由の置換。選択状態が残っている前面アプリに⌘Vを送る。
    private static func pasteReplace(text: String, targetPID: pid_t?) -> Bool {
        let pasteboard = NSPasteboard.general
        let saved = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // 対象アプリが前面でなければ前面に戻す（nonactivating panelなので通常は前面のまま）
        var needsActivationDelay = false
        if let pid = targetPID,
           NSWorkspace.shared.frontmostApplication?.processIdentifier != pid {
            needsActivationDelay = true
            NSRunningApplication(processIdentifier: pid)?.activate()
            logger.log("対象アプリ(pid=\(pid))を前面化してからペーストする")
        }

        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            logger.log("CGEventSource作成に失敗")
            return false
        }
        let vKey: CGKeyCode = 0x09
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        else {
            logger.log("CGEvent作成に失敗")
            return false
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        // Chrome/Electron系はpid宛イベントを無視するため、HIDタップ宛に送る
        Task { @MainActor in
            if needsActivationDelay {
                try? await Task.sleep(for: .milliseconds(150))
            }
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
            logger.log("⌘VをHIDタップへ送信")

            // ペースト処理が終わった頃にクリップボードを復元する
            if let saved {
                try? await Task.sleep(for: .milliseconds(500))
                pasteboard.clearContents()
                pasteboard.setString(saved, forType: .string)
            }
        }
        return true
    }
}
