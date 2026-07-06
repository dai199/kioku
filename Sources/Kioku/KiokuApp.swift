import SwiftUI

@main
struct KiokuApp: App {
    @StateObject private var coordinator = AppCoordinator()

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environmentObject(coordinator)
                .environmentObject(coordinator.permission)
        } label: {
            MenuBarIcon()
                .environmentObject(coordinator.permission)
        }
    }
}

private struct MenuBarIcon: View {
    @EnvironmentObject private var permission: AccessibilityPermission

    var body: some View {
        // メニューバーはモノクロのテンプレート画像が正（HIG: The menu bar）。
        // テンプレート指定によりライト/ダーク・選択状態の色反転はOSが面倒を見る
        Image(systemName: permission.isTrusted
            ? "translate"
            : "exclamationmark.triangle.fill")
            .renderingMode(.template)
            .accessibilityLabel("Kioku")
    }
}
