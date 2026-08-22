import AppKit
import CoreGraphics
import XCTest

/// サイト用のスクリーンショットを実アプリから撮る。
///
/// 実物をそのまま撮るので、ウィンドウの枠も素材の質感も本物になる
/// （オフスクリーン描画では再現できない）。代わりに画面を専有するので、
/// `make screenshots` からのみ回す。通常のテストとは分けてある。
///
/// アプリは `-KiokuDemo` で起動する。見本データのインメモリDBと定型の訳が使われ、
/// 実際の翻訳履歴もAPIキーも要らない。
final class Screenshots: XCTestCase {
    /// 出力先。UIテストランナーはサンドボックス内で動くのでリポジトリには書けない。
    /// 自分の領域に出し、`make screenshots` が取り出す
    private var outputDirectory: URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("kioku-screenshots", isDirectory: true)
    }

    /// ライトとダークは`make screenshots`が2周に分けて回す。
    /// テキストエディット側の見た目もそちらで揃えるので、テストは指示に従うだけ
    private var appearance: String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let value = try? String(contentsOf: root.appendingPathComponent(".shot-appearance"),
                                encoding: .utf8)
        return value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "light"
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        try FileManager.default.createDirectory(
            at: outputDirectory, withIntermediateDirectories: true
        )
    }

    func testCaptureWindows() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-KiokuDemo", "-KiokuAppearance", appearance]
        app.launch()

        let statusItem = app.menuBars.children(matching: .statusItem).element(boundBy: 0)
        XCTAssertTrue(statusItem.waitForExistence(timeout: 10), "メニューバー項目が出ない")

        for screen in Screen.allCases {
            try capture(screen, in: app, statusItem: statusItem)
        }
        app.terminate()
    }

    // MARK: - ウィンドウ

    private enum Screen: String, CaseIterable {
        case report = "週次レポート…"
        case review = "復習する…"
        case history = "翻訳履歴…"

        var fileName: String {
            switch self {
            case .report: "report"
            case .review: "review"
            case .history: "history"
            }
        }
    }

    private func capture(_ screen: Screen, in app: XCUIApplication, statusItem: XCUIElement) throws {
        statusItem.click()
        // 未読があると「週次レポート… ●」のように印が付くので前方一致で拾う
        let item = statusItem.descendants(matching: .menuItem)
            .matching(NSPredicate(format: "title BEGINSWITH %@", screen.rawValue)).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5), "\(screen.rawValue) が見つからない")
        item.click()

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10), "ウィンドウが開かない")
        // 表示とレイアウトが落ち着くのを待つ。DB監視の反映が1フレーム遅れることがある
        Thread.sleep(forTimeInterval: 1.5)

        collapseSidebar(in: window)

        try write(window.screenshot().pngRepresentation, as: screen.fileName)
    }

    /// 3枚とも同じサイドバーが写るので畳んでから撮る。
    /// 表示幅を変えずに中身だけ大きくできる（同じものが3回出ても意味がない）。
    /// 開閉はアプリが前回の状態を復元するので、畳まれるまで押す
    private func collapseSidebar(in window: XCUIElement) {
        let toggle = window.buttons
            .matching(NSPredicate(format: "label IN {'サイドバー', 'Sidebar'}")).firstMatch
        guard toggle.waitForExistence(timeout: 5) else { return }
        for _ in 0..<2 {
            let sidebar = window.descendants(matching: .any)
                .matching(NSPredicate(format: "label == 'Sidebar'")).firstMatch
            guard sidebar.exists, sidebar.frame.width > 40 else { return }
            toggle.click()
            Thread.sleep(forTimeInterval: 1.2)
        }
    }

    // MARK: - ポップアップ

    /// 他アプリのテキストを選んで訳す、という本来の使い方をそのまま撮る。
    ///
    /// テキストエディットを相手にするのは、選択範囲の画面座標をAXで正しく返す
    /// 数少ないアプリだから（CLAUDE.mdの実測表を参照）。
    func testCapturePopup() throws {
        // 保存済みのファイルを開くだけにする。書類を書き換えないので、
        // 閉じるときに保存を聞かれず、未保存の無題書類も溜まらない。
        // 日本語を`typeText`で打つと入力ソースの切り替え許可を毎回求められる、という事情もある
        let fixture = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("Kioku.txt")
        try "確認して折り返します。".write(to: fixture, atomically: true, encoding: .utf8)

        let kioku = XCUIApplication()
        kioku.launchArguments = ["-KiokuDemo", "-KiokuAppearance", appearance]
        kioku.launch()
        Thread.sleep(forTimeInterval: 2.5)

        let editor = XCUIApplication(bundleIdentifier: "com.apple.TextEdit")
        editor.launch()
        Thread.sleep(forTimeInterval: 2)
        closeDocuments(of: editor)

        let opener = Process()
        opener.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        opener.arguments = ["-a", "TextEdit", fixture.path]
        try opener.run()
        opener.waitUntilExit()

        let window = editor.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 15), "見本が開かない")
        Thread.sleep(forTimeInterval: 1)
        move(window, to: CGPoint(x: 240, y: 180))

        // ポップアップは本文の左端より外側にはみ出す。他のアプリを隠して、
        // その部分に作業中の画面が写り込まないようにする
        editor.typeKey("h", modifierFlags: [.command, .option])
        Thread.sleep(forTimeInterval: 1.5)

        let area = window.textViews.firstMatch
        XCTAssertTrue(area.waitForExistence(timeout: 10))
        tripleClick(at: CGPoint(x: area.frame.minX + 20, y: area.frame.minY + 16))
        let icon = try XCTUnwrap(waitForKiokuWindow(minWidth: 0), "アイコンが出ない")
        click(at: CGPoint(x: icon.midX, y: icon.midY))
        let popup = try XCTUnwrap(waitForKiokuWindow(minWidth: 200), "ポップアップが出ない")
        // 訳が出そろってから撮る
        Thread.sleep(forTimeInterval: 2)

        // 選択中の原文とポップアップが両方入るところだけを切り出す
        let top = window.frame.minY - 18
        let region = CGRect(x: popup.minX - 28, y: top,
                            width: popup.width + 56, height: popup.maxY + 22 - top)
        print("SHOT_geometry window=\(window.frame) icon=\(icon) popup=\(popup) region=\(region)")
        // 常駐して他アプリのテキスト欄にボタンを重ねるツールは「ほかを隠す」では消えず、
        // 黙って写り込む。気づかず公開しないよう、ここで止める
        let intruders = owners(overlapping: region)
            .filter { !["テキストエディット", "TextEdit", "Kioku", "Window Server",
                        "AutomationModeUI", "Dock", "Finder"].contains($0) }
        XCTAssertTrue(intruders.isEmpty,
                      "撮影範囲に別のアプリが重なっている: \(intruders.joined(separator: ", "))"
                        + "（終了させてから撮り直してください）")
        try write(crop(XCUIScreen.main.screenshot(), to: region), as: "popup")

        closeDocuments(of: editor)
        editor.terminate()
        kioku.terminate()
        for hidden in NSWorkspace.shared.runningApplications where hidden.isHidden {
            hidden.unhide()
        }
    }

    /// 前に開いた書類が残っていると背景に写り込む。保存を聞かれたら破棄する
    /// （破棄のボタン名はmacOSの版で変わるので、保存とキャンセル以外を押す）
    private func closeDocuments(of app: XCUIApplication) {
        for _ in 0..<10 {
            guard app.windows.firstMatch.exists else { return }
            app.typeKey("w", modifierFlags: .command)
            Thread.sleep(forTimeInterval: 0.9)
            guard app.sheets.firstMatch.exists else { continue }
            let keep: Set<String> = ["保存", "保存…", "別名で保存…", "キャンセル", "Save", "Cancel"]
            let discard = app.sheets.buttons.allElementsBoundByIndex
                .first { !keep.contains($0.title) }
            discard?.click()
            Thread.sleep(forTimeInterval: 0.9)
        }
    }

    private func post(_ type: CGEventType, at point: CGPoint, clickState: Int64 = 1) {
        let event = CGEvent(mouseEventSource: nil, mouseType: type,
                            mouseCursorPosition: point, mouseButton: .left)
        event?.setIntegerValueField(.mouseEventClickState, value: clickState)
        event?.post(tap: .cghidEventTap)
    }

    /// XCUITestのクリックは対象を前面に出そうとする。フォーカスを奪わない
    /// ポップアップを相手にするので、実際のクリックと同じイベントを送る
    private func click(at point: CGPoint) {
        post(.mouseMoved, at: point)
        Thread.sleep(forTimeInterval: 0.15)
        post(.leftMouseDown, at: point)
        Thread.sleep(forTimeInterval: 0.08)
        post(.leftMouseUp, at: point)
    }

    /// 合成イベントのドラッグは途中の移動が省かれ、テキスト側が範囲選択と
    /// 認識しない（実測）。行をまるごと選ぶトリプルクリックなら確実に通る
    private func tripleClick(at point: CGPoint) {
        post(.mouseMoved, at: point)
        Thread.sleep(forTimeInterval: 0.1)
        for state in Int64(1)...3 {
            post(.leftMouseDown, at: point, clickState: state)
            Thread.sleep(forTimeInterval: 0.04)
            post(.leftMouseUp, at: point, clickState: state)
            Thread.sleep(forTimeInterval: 0.05)
        }
    }

    /// ウィンドウは前回の位置に復元される。別ディスプレイに出ることもあるので、
    /// タイトルバーを掴んで定位置へ移す
    private func move(_ window: XCUIElement, to target: CGPoint) {
        let delta = CGVector(dx: target.x - window.frame.minX, dy: target.y - window.frame.minY)
        guard abs(delta.dx) > 1 || abs(delta.dy) > 1 else { return }
        let corner = window.coordinate(withNormalizedOffset: .zero)
        corner.withOffset(CGVector(dx: window.frame.width / 2, dy: 12))
            .press(forDuration: 0.4, thenDragTo: corner.withOffset(
                CGVector(dx: window.frame.width / 2 + delta.dx, dy: 12 + delta.dy)))
        Thread.sleep(forTimeInterval: 1)
    }

    // MARK: - 画面を見る

    /// Kiokuが出しているウィンドウをAXに頼らず拾う。
    /// フローティングアイコンもポップアップもAXツリーには現れない
    private func waitForKiokuWindow(minWidth: CGFloat, seconds: Double = 8) -> CGRect? {
        for _ in 0..<Int(seconds / 0.3) {
            Thread.sleep(forTimeInterval: 0.3)
            let list = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            guard let windows = list as? [[String: Any]] else { continue }
            let rects = windows.compactMap { window -> CGRect? in
                guard (window[kCGWindowOwnerName as String] as? String) == "Kioku",
                      let raw = window[kCGWindowBounds as String] as? [String: CGFloat]
                else { return nil }
                return CGRect(dictionaryRepresentation: raw as CFDictionary)
            }
            if let rect = rects.first(where: { $0.width >= minWidth }) { return rect }
        }
        return nil
    }

    private func owners(overlapping rect: CGRect) -> [String] {
        let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
        guard let windows = list as? [[String: Any]] else { return [] }
        return Array(Set(windows.compactMap { window in
            guard let raw = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let bounds = CGRect(dictionaryRepresentation: raw as CFDictionary),
                  bounds.intersects(rect)
            else { return nil }
            return window[kCGWindowOwnerName as String] as? String ?? "?"
        })).sorted()
    }

    private func crop(_ screenshot: XCUIScreenshot, to rect: CGRect) -> Data {
        let display = CGDisplayBounds(CGMainDisplayID())
        guard let cgImage = screenshot.image
            .cgImage(forProposedRect: nil, context: nil, hints: nil),
            display.width > 0
        else { return screenshot.pngRepresentation }
        // ウィンドウの座標はポイント、画像はピクセル。Retinaぶんを掛けて切り出す。
        // 倍率は画面から取る（`XCUIScreenshot`の画像サイズは既にピクセル）
        let scale = CGFloat(cgImage.width) / display.width
        let pixels = CGRect(x: rect.minX * scale, y: rect.minY * scale,
                            width: rect.width * scale, height: rect.height * scale)
        guard let cropped = cgImage.cropping(to: pixels) else { return screenshot.pngRepresentation }
        return NSBitmapImageRep(cgImage: cropped)
            .representation(using: NSBitmapImageRep.FileType.png, properties: [:])
            ?? screenshot.pngRepresentation
    }

    private func write(_ data: Data, as name: String) throws {
        let file = outputDirectory.appendingPathComponent("\(name)-\(appearance).png")
        try data.write(to: file)
        print("SHOT \(file.lastPathComponent)")
    }
}
