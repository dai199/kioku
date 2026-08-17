import SwiftUI

@main
struct KiokuApp: App {
    @StateObject private var coordinator = AppCoordinator()

    init() {
        DemoMode.applyAppearanceOverride()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environmentObject(coordinator)
                .environmentObject(coordinator.permission)
                .environmentObject(coordinator.unread)
        } label: {
            MenuBarIcon()
                .environmentObject(coordinator.permission)
                .environmentObject(coordinator.unread)
        }
    }
}

private struct MenuBarIcon: View {
    @EnvironmentObject private var permission: AccessibilityPermission
    @EnvironmentObject private var unread: UnreadReportTracker

    var body: some View {
        // メニューバーはモノクロのテンプレート画像が正（HIG: The menu bar）。
        // テンプレート指定によりライト/ダーク・選択状態の色反転はOSが面倒を見る
        if permission.isTrusted {
            Image(nsImage: unread.hasUnreadReport ? BrandIcon.templateWithBadge : BrandIcon.template)
                .accessibilityLabel(unread.hasUnreadReport ? "Kioku（未読のレポートあり）" : "Kioku")
        } else {
            Image(systemName: "exclamationmark.triangle.fill")
                .renderingMode(.template)
                .accessibilityLabel("Kioku（権限が必要）")
        }
    }
}
