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
        Image(systemName: permission.isTrusted
            ? "character.book.closed.fill"
            : "exclamationmark.triangle.fill")
    }
}
