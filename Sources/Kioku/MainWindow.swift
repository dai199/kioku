import AppKit
import Combine
import SwiftUI

/// メインウィンドウのサイドバー項目。
/// 「学習データを見る」画面はすべてここに集約する（設定は独立ウィンドウのまま: HIGの⌘,慣習）。
enum MainSection: String, CaseIterable, Identifiable {
    case review
    case history
    case report

    var id: String { rawValue }

    var title: String {
        switch self {
        case .review: "復習"
        case .history: "翻訳履歴"
        case .report: "週次レポート"
        }
    }

    var symbol: String {
        switch self {
        case .review: "square.stack"
        case .history: "clock"
        case .report: "chart.line.uptrend.xyaxis"
        }
    }
}

/// メインウィンドウ全体の状態。
/// 履歴・レポートのモデルはここが保持し、画面を切り替えてもDB監視が張り直されないようにする。
/// 復習だけはセッション単位なので、開くたび・切り替えるたびに作り直す（`sessionID`）。
@MainActor
final class MainWindowModel: ObservableObject {
    @Published var section: MainSection = .review
    @Published var sidebarVisibility: NavigationSplitViewVisibility = .all
    @Published private(set) var reviewSessionID = 0

    let history = HistoryModel()
    let report = ReportModel()
    let reportManager: ReportManager
    let unread: UnreadReportTracker

    init(reportManager: ReportManager, unread: UnreadReportTracker) {
        self.reportManager = reportManager
        self.unread = unread
    }

    /// 復習セッションを仕切り直す。
    func restartReview() {
        reviewSessionID += 1
    }

    func toggleSidebar() {
        withAnimation {
            sidebarVisibility = sidebarVisibility == .detailOnly ? .all : .detailOnly
        }
    }
}

/// メインウィンドウ（復習・翻訳履歴・週次レポート）。
@MainActor
final class MainWindowController {
    private let model: MainWindowModel
    private var window: NSWindow?
    private var cancellable: AnyCancellable?
    private var toolbarDelegate: MainToolbarDelegate?

    init(reportManager: ReportManager, unread: UnreadReportTracker) {
        model = MainWindowModel(reportManager: reportManager, unread: unread)
    }

    func show(_ section: MainSection) {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 760, height: 540),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.isReleasedWhenClosed = false
            window.contentMinSize = NSSize(width: 620, height: 420)
            window.contentView = NSHostingView(
                rootView: MainView(model: model, unread: model.unread)
            )
            window.center()
            window.setFrameAutosaveName("KiokuMainWindow")

            // サイドバーの開閉ボタンはウィンドウのツールバーに置く。
            // NavigationSplitView組み込みのボタンはカラムに追従して位置が動くため、
            // ウィンドウ座標に固定されるツールバー項目（末尾）に自前で用意する
            let delegate = MainToolbarDelegate(
                model: model,
                onToggleSidebar: { [weak self] in self?.model.toggleSidebar() }
            )
            let toolbar = NSToolbar(identifier: "KiokuMainToolbar")
            toolbar.delegate = delegate
            toolbar.displayMode = .iconOnly
            toolbar.allowsUserCustomization = false
            window.toolbar = toolbar
            window.toolbarStyle = .unified
            toolbarDelegate = delegate

            self.window = window
            // サイドバーの選択をウィンドウタイトルとツールバーの内容に反映する
            cancellable = model.$section
                .removeDuplicates()
                .sink { [weak self, weak window] section in
                    window?.title = section.title
                    if let toolbar = window?.toolbar {
                        MainToolbarDelegate.updateItems(in: toolbar, for: section)
                    }
                    // レポート画面を開いた時点で既読
                    if section == .report {
                        self?.model.unread.markReportSeen()
                    }
                }
        }
        // 復習は開くたびにセッションを仕切り直す
        if section == .review { model.restartReview() }
        model.section = section
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

/// ウィンドウのツールバー。位置がカラムに追従しないよう、項目はすべて自前で用意する。
/// - サイドバー開閉ボタン（常時）
/// - 週次レポートの週メニュー（レポート画面のときだけ挿入する）
@MainActor
private final class MainToolbarDelegate: NSObject, NSToolbarDelegate, NSMenuDelegate {
    private static let toggle = NSToolbarItem.Identifier("KiokuSidebarToggle")
    static let reportWeek = NSToolbarItem.Identifier("KiokuReportWeek")

    private let model: MainWindowModel
    private let onToggleSidebar: () -> Void

    init(model: MainWindowModel, onToggleSidebar: @escaping () -> Void) {
        self.model = model
        self.onToggleSidebar = onToggleSidebar
    }

    /// 画面に応じて週メニューを出し入れする。
    static func updateItems(in toolbar: NSToolbar, for section: MainSection) {
        let index = toolbar.items.firstIndex { $0.itemIdentifier == reportWeek }
        switch (section, index) {
        case (.report, nil):
            // 末尾のサイドバーボタンの手前に置く
            toolbar.insertItem(withItemIdentifier: reportWeek, at: max(toolbar.items.count - 1, 0))
        case (_, .some(let index)) where section != .report:
            toolbar.removeItem(at: index)
        default:
            break
        }
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, Self.toggle]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, Self.reportWeek, Self.toggle]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier identifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch identifier {
        case Self.toggle:
            let item = NSToolbarItem(itemIdentifier: identifier)
            item.label = "サイドバー"
            item.toolTip = "サイドバーの表示を切り替える"
            item.image = NSImage(
                systemSymbolName: "sidebar.leading",
                accessibilityDescription: "サイドバーの表示を切り替える"
            )
            item.isBordered = true
            item.target = self
            item.action = #selector(toggleSidebar(_:))
            return item

        case Self.reportWeek:
            let item = NSMenuToolbarItem(itemIdentifier: identifier)
            item.label = "週"
            item.toolTip = "表示する週を選ぶ"
            item.image = NSImage(
                systemSymbolName: "calendar",
                accessibilityDescription: "表示する週を選ぶ"
            )
            let menu = NSMenu()
            menu.delegate = self  // 開くたびに最新の一覧に作り直す
            item.menu = menu
            return item

        default:
            return nil
        }
    }

    // MARK: - 週メニュー

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let reports = model.report.reports
        guard !reports.isEmpty else {
            let empty = NSMenuItem(title: "レポートがありません", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
            return
        }
        let selectedID = model.report.selectedReport?.id
        for (index, report) in reports.enumerated() {
            let item = NSMenuItem(
                title: Self.title(for: report, isLatest: index == 0),
                action: #selector(selectWeek(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = report.id
            item.state = report.id == selectedID ? .on : .off
            menu.addItem(item)
        }
    }

    private static func title(for report: WeeklyReportRecord, isLatest: Bool) -> String {
        let format = Date.FormatStyle().month(.defaultDigits).day()
        let period = "\(report.periodStart.formatted(format)) 〜 \(report.periodEnd.formatted(format))"
        return isLatest ? "\(period)（最新）" : period
    }

    @objc private func selectWeek(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? Int64 else { return }
        // 最新を選んだときは「常に最新を追う」状態に戻す
        model.report.selectedReportID = id == model.report.reports.first?.id ? nil : id
    }

    @objc private func toggleSidebar(_ sender: Any?) {
        onToggleSidebar()
    }
}

struct MainView: View {
    @ObservedObject var model: MainWindowModel
    /// 未読状態は別のObservableObjectなので、更新を受けるためここでも購読する
    @ObservedObject var unread: UnreadReportTracker

    /// 未読レポートがある間だけ、サイドバーの該当項目に印を出す。
    private func unreadBadge(for section: MainSection) -> Text? {
        guard section == .report, unread.hasUnreadReport else { return nil }
        return Text("●")
    }

    var body: some View {
        // サイドバーは固定幅（ドラッグでの幅変更はしない）。開閉はツールバーのボタンで行う
        NavigationSplitView(columnVisibility: $model.sidebarVisibility) {
            List(MainSection.allCases, selection: selectionBinding) { section in
                Label(section.title, systemImage: section.symbol)
                    .badge(unreadBadge(for: section))
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(180)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// サイドバーで復習を選び直したときもセッションを仕切り直す。
    private var selectionBinding: Binding<MainSection?> {
        Binding(
            get: { model.section },
            set: { newValue in
                guard let newValue else { return }
                if newValue == .review { model.restartReview() }
                model.section = newValue
            }
        )
    }

    @ViewBuilder
    private var detail: some View {
        switch model.section {
        case .review:
            ReviewView(model: ReviewModel())
                .id(model.reviewSessionID)
        case .history:
            HistoryView(model: model.history)
        case .report:
            ReportView(model: model.report, manager: model.reportManager)
        }
    }
}
