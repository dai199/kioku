import AppKit
import Combine

/// 権限・選択監視・フローティングアイコン・ポップアップを束ねる中枢。
@MainActor
final class AppCoordinator: ObservableObject {
    let permission = AccessibilityPermission()
    let settings = AppSettings()
    let unread = UnreadReportTracker()

    @Published var isMonitoringEnabled = true {
        didSet { updateMonitorState() }
    }

    private let monitor = SelectionMonitor()
    private let floatingIcon = FloatingIconController()
    private let popup = PopupController()
    private lazy var settingsWindow = SettingsWindowController(settings: settings)
    private lazy var reportManager = ReportManager(settings: settings)
    private lazy var mainWindow = MainWindowController(
        reportManager: reportManager, unread: unread
    )
    private var notificationRouter: NotificationRouter?
    private let translationCache = TranslationCache()
    private var currentEvent: SelectionEvent?
    /// スペース復帰時の再表示判定に使う「最近認識した選択」（AX要素は持たない軽量記録）
    private var recentSelections: [(text: String, bundleID: String?, at: Date)] = []
    private var respawnTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    init() {
        monitor.onSelection = { [weak self] event in
            self?.handleSelection(event)
        }
        monitor.onInteractionStarted = { [weak self] in
            self?.floatingIcon.hide()
            self?.popup.hide()
        }
        floatingIcon.onClick = { [weak self] in
            self?.openPopup()
        }

        permission.$isTrusted
            .removeDuplicates()
            .sink { [weak self] _ in
                Task { @MainActor in self?.updateMonitorState() }
            }
            .store(in: &cancellables)

        // スペース（デスクトップ）を切り替えたら、前のスペースの選択に紐づくUIは閉じる。
        // その後、移動先のスペースに「最近認識した選択」がまだ生きていれば再表示する
        // （元のデスクトップに戻ってきたケース）。
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.floatingIcon.hide()
                self.popup.hide()
                self.currentEvent = nil
                self.respawnTask?.cancel()
                self.respawnTask = Task { @MainActor [weak self] in
                    // スペース切替のアニメーションが落ち着くのを待ってから再プローブ
                    try? await Task.sleep(for: .milliseconds(350))
                    guard !Task.isCancelled else { return }
                    self?.reshowIconIfSelectionPersists()
                }
            }
        }

        reportManager.startAutoCheck()
        // 通知タップで該当画面を開けるようにする（配信より前にデリゲートを立てる）
        notificationRouter = NotificationRouter(coordinator: self)
    }

    private func updateMonitorState() {
        if permission.isTrusted && isMonitoringEnabled {
            monitor.start()
        } else {
            monitor.stop()
            floatingIcon.hide()
            popup.hide()
        }
    }

    private func handleSelection(_ event: SelectionEvent) {
        currentEvent = event
        rememberSelection(event)
        // 選択範囲の右上に出す（AX座標→ドラッグ2点からの推定→マウス位置の順）
        floatingIcon.show(near: event.iconAnchor)
    }

    private func rememberSelection(_ event: SelectionEvent) {
        recentSelections.append((text: event.text, bundleID: event.bundleID, at: Date()))
        pruneRecentSelections()
    }

    private func pruneRecentSelections() {
        let cutoff = Date().addingTimeInterval(-5 * 60)
        recentSelections.removeAll { $0.at < cutoff }
        if recentSelections.count > 10 {
            recentSelections.removeFirst(recentSelections.count - 10)
        }
    }

    /// スペース切替後、前面アプリの選択が「最近認識した選択」と一致していれば
    /// アイコンを出し直す（元のデスクトップに戻ってきたケース）。
    private func reshowIconIfSelectionPersists() {
        guard permission.isTrusted, isMonitoringEnabled else { return }
        pruneRecentSelections()
        guard let event = SelectionEvent(probe: SelectionProbe.readCurrentSelection()),
              recentSelections.contains(where: {
                  $0.text == event.text && $0.bundleID == event.bundleID
              })
        else { return }
        handleSelection(event)
    }

    private func openPopup() {
        guard let event = currentEvent else { return }
        floatingIcon.hide()
        let session = TranslationSession(
            event: event,
            engine: settings.makeEngine(),
            cache: translationCache
        )
        popup.show(session: session) { [weak self] in
            self?.openSettings()
        }
    }

    func openSettings() {
        settingsWindow.show()
    }

    func open(_ section: MainSection) {
        mainWindow.show(section)
    }

    func openHistory() {
        open(.history)
    }

    func openReport() {
        open(.report)
    }

    func openReview() {
        open(.review)
    }
}
