import UserNotifications

/// 通知タップの行き先を決める。
/// 通知に入れた区画（`section`）に対応する画面をメインウィンドウで開く。
@MainActor
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    nonisolated static let sectionKey = "section"

    private weak var coordinator: AppCoordinator?

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    /// メニューバーアプリはウィンドウを開いたまま前面にいることがあるので、
    /// 前面でもバナーを出す（出さないとOSに握り潰される）。
    /// デリゲートの引数はSendableでないため、メインアクター外で受けて必要な値だけ渡す。
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let raw = response.notification.request.content.userInfo[Self.sectionKey] as? String
        Task { @MainActor [weak self] in
            guard let section = raw.flatMap(MainSection.init(rawValue:)) else { return }
            self?.coordinator?.open(section)
        }
        completionHandler()
    }
}
