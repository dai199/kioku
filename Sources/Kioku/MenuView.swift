import AppKit
import SwiftUI

struct MenuView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @EnvironmentObject private var permission: AccessibilityPermission

    var body: some View {
        if permission.isTrusted {
            Toggle("選択検知を有効にする", isOn: $coordinator.isMonitoringEnabled)
            Divider()
            Button("選択テキストをテスト取得") {
                showProbeResult()
            }
        } else {
            Text("アクセシビリティ権限が必要です")
            Button("権限をリクエスト…") {
                permission.prompt()
            }
            Button("システム設定を開く…") {
                permission.openSystemSettings()
            }
        }
        Divider()
        Button("復習する…") {
            coordinator.openReview()
        }
        .keyboardShortcut("s")
        Button("翻訳履歴…") {
            coordinator.openHistory()
        }
        .keyboardShortcut("h")
        Button("週次レポート…") {
            coordinator.openReport()
        }
        .keyboardShortcut("r")
        Button("設定…") {
            coordinator.openSettings()
        }
        .keyboardShortcut(",")
        Divider()
        Button("Kiokuを終了") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    /// メニュー選択時点ではフォーカスは前面アプリに残っているため、
    /// そのアプリの選択テキストをAX経由で読み、結果をアラートで表示する。
    private func showProbeResult() {
        let probe = SelectionProbe.readCurrentSelection()

        let alert = NSAlert()
        if let text = probe.text {
            alert.messageText = "選択テキストを取得できました"
            let source = probe.appName.map { "出典アプリ: \($0)\n\n" } ?? ""
            alert.informativeText = source + text
        } else {
            alert.messageText = "選択テキストを取得できませんでした"
            let source = probe.appName.map { "前面アプリ: \($0)\n" } ?? ""
            alert.informativeText = source + probe.detail
        }
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
