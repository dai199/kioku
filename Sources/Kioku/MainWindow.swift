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

    init(reportManager: ReportManager) {
        self.reportManager = reportManager
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
    private var toolbarDelegate: SidebarToolbarDelegate?

    init(reportManager: ReportManager) {
        model = MainWindowModel(reportManager: reportManager)
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
            window.contentView = NSHostingView(rootView: MainView(model: model))
            window.center()
            window.setFrameAutosaveName("KiokuMainWindow")

            // サイドバーの開閉ボタンはウィンドウのツールバーに置く。
            // NavigationSplitView組み込みのボタンはカラムに追従して位置が動くため、
            // ウィンドウ座標に固定されるツールバー項目（末尾）に自前で用意する
            let delegate = SidebarToolbarDelegate { [weak self] in
                self?.model.toggleSidebar()
            }
            let toolbar = NSToolbar(identifier: "KiokuMainToolbar")
            toolbar.delegate = delegate
            toolbar.displayMode = .iconOnly
            toolbar.allowsUserCustomization = false
            window.toolbar = toolbar
            window.toolbarStyle = .unified
            toolbarDelegate = delegate

            self.window = window
            // サイドバーの選択をウィンドウタイトルに反映する
            cancellable = model.$section
                .removeDuplicates()
                .sink { [weak window] section in
                    window?.title = section.title
                }
        }
        // 復習は開くたびにセッションを仕切り直す
        if section == .review { model.restartReview() }
        model.section = section
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

/// ツールバー末尾に置くサイドバー開閉ボタン。
@MainActor
private final class SidebarToolbarDelegate: NSObject, NSToolbarDelegate {
    private static let toggle = NSToolbarItem.Identifier("KiokuSidebarToggle")

    private let onToggle: () -> Void

    init(onToggle: @escaping () -> Void) {
        self.onToggle = onToggle
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, Self.toggle]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier identifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard identifier == Self.toggle else { return nil }
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = "サイドバー"
        item.toolTip = "サイドバーの表示を切り替える"
        item.image = NSImage(
            systemSymbolName: "sidebar.leading",
            accessibilityDescription: "サイドバーの表示を切り替える"
        )
        item.isBordered = true
        item.target = self
        item.action = #selector(toggle(_:))
        return item
    }

    @objc private func toggle(_ sender: Any?) {
        onToggle()
    }
}

struct MainView: View {
    @ObservedObject var model: MainWindowModel

    var body: some View {
        // サイドバーは固定幅（ドラッグでの幅変更はしない）。開閉はツールバーのボタンで行う
        NavigationSplitView(columnVisibility: $model.sidebarVisibility) {
            List(MainSection.allCases, selection: selectionBinding) { section in
                Label(section.title, systemImage: section.symbol)
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
