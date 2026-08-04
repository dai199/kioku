import Combine
import Foundation
import GRDB

/// 週次レポートの未読状態。メニューバーアイコン・メニュー項目・サイドバーの
/// 3か所が同じ状態を見るよう、ここ1か所で持つ。
/// 既読の定義は「レポート画面を開いた時点」。
@MainActor
final class UnreadReportTracker: ObservableObject {
    @Published private(set) var hasUnreadReport = false

    private static let lastSeenKey = "lastSeenReportID"

    private var latestReportID: Int64?
    private var cancellable: AnyDatabaseCancellable?

    init() {
        cancellable = ValueObservation
            .tracking { db in
                try WeeklyReportRecord
                    .order(Column("generatedAt").desc)
                    .selectPrimaryKey(as: Int64.self)
                    .fetchOne(db)
            }
            .start(
                in: DatabaseManager.shared.dbQueue,
                onError: { NSLog("未読レポートの監視に失敗: \($0)") },
                onChange: { id in
                    Task { @MainActor [weak self] in
                        self?.latestReportID = id
                        self?.refresh()
                    }
                }
            )
    }

    func markReportSeen() {
        guard let latestReportID else { return }
        UserDefaults.standard.set(Int(latestReportID), forKey: Self.lastSeenKey)
        refresh()
    }

    private func refresh() {
        guard let latestReportID else {
            hasUnreadReport = false
            return
        }
        // 未設定（初回）は未読扱い
        let lastSeen = UserDefaults.standard.object(forKey: Self.lastSeenKey) as? Int
        hasUnreadReport = lastSeen.map { Int64($0) != latestReportID } ?? true
    }
}
