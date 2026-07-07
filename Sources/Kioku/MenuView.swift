import AppKit
import SwiftUI

struct MenuView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @EnvironmentObject private var permission: AccessibilityPermission

    var body: some View {
        if permission.isTrusted {
            Toggle("選択検知を有効にする", isOn: $coordinator.isMonitoringEnabled)
        } else {
            Text("アクセシビリティ権限が必要です")
            Button {
                permission.prompt()
            } label: {
                Label("権限をリクエスト…", systemImage: "lock.shield")
            }
            Button {
                permission.openSystemSettings()
            } label: {
                Label("システム設定を開く…", systemImage: "gearshape.arrow.trianglehead.2.clockwise.rotate.90")
            }
        }
        Divider()
        Button {
            coordinator.openReview()
        } label: {
            Label("復習する…", systemImage: "square.stack")
        }
        .keyboardShortcut("s")
        Button {
            coordinator.openHistory()
        } label: {
            Label("翻訳履歴…", systemImage: "clock")
        }
        .keyboardShortcut("h")
        Button {
            coordinator.openReport()
        } label: {
            Label("週次レポート…", systemImage: "chart.line.uptrend.xyaxis")
        }
        .keyboardShortcut("r")
        Button {
            coordinator.openSettings()
        } label: {
            Label("設定…", systemImage: "gearshape")
        }
        .keyboardShortcut(",")
        Divider()
        Button("Kiokuを終了") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
