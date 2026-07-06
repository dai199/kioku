import Foundation
import UserNotifications

/// 週次レポートの生成を司る。手動生成に加え、
/// 「前回から7日以上経過し、期間内にログがある」場合に自動生成して通知する。
@MainActor
final class ReportManager: ObservableObject {
    @Published private(set) var isGenerating = false
    @Published private(set) var lastError: String?

    /// 自動生成の条件: 期間内に最低このログ数がないと分析しない
    private static let minimumLogCount = 5
    private static let weekInterval: TimeInterval = 7 * 24 * 3600

    private let settings: AppSettings
    private let store: DatabaseManager
    private var autoCheckTask: Task<Void, Never>?

    init(settings: AppSettings, store: DatabaseManager = .shared) {
        self.settings = settings
        self.store = store
    }

    /// 起動30秒後に1回チェックし、以降6時間ごとに繰り返す。
    func startAutoCheck() {
        guard autoCheckTask == nil else { return }
        autoCheckTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(30))
            while !Task.isCancelled {
                guard let self else { return }
                await self.autoGenerateIfDue()
                try? await Task.sleep(for: .seconds(6 * 3600))
            }
        }
    }

    private func autoGenerateIfDue() async {
        guard settings.hasAPIKey, !isGenerating else { return }
        guard let last = try? await store.latestReport() else {
            // レポート未生成: ログが貯まっていれば初回生成
            await generate(notify: true, requireMinimumLogs: true)
            return
        }
        if Date().timeIntervalSince(last.generatedAt) >= Self.weekInterval {
            await generate(notify: true, requireMinimumLogs: true)
        }
    }

    /// レポートを生成して保存する。カード候補はproposed状態で登録される。
    func generate(notify: Bool, requireMinimumLogs: Bool = false) async {
        guard !isGenerating else { return }
        isGenerating = true
        lastError = nil
        defer { isGenerating = false }

        do {
            let end = Date()
            let start = end.addingTimeInterval(-Self.weekInterval)
            let logs = try await store.fetchLogs(from: start, to: end)

            if logs.isEmpty {
                lastError = "この1週間の翻訳ログがありません。"
                return
            }
            if requireMinimumLogs, logs.count < Self.minimumLogCount {
                return // 自動生成はログが貯まるまで静かに見送る
            }

            let client = GeminiClient(
                apiKey: settings.geminiAPIKey,
                model: settings.analysisModel
            )
            let analysis = try await WeeklyAnalyzer(client: client).analyze(logs: logs)

            let content = WeeklyReportContent(
                stats: Self.stats(for: logs),
                analysis: analysis
            )
            let contentJSON = String(
                data: try JSONEncoder().encode(content), encoding: .utf8
            ) ?? "{}"

            let now = Date()
            let cards = analysis.cards
                .filter { !$0.front.isEmpty && !$0.back.isEmpty }
                .map { proposal in
                    SRSCard(
                        id: nil,
                        createdAt: now,
                        logId: proposal.logId,
                        front: proposal.front,
                        back: proposal.back,
                        reason: proposal.reason,
                        origin: SRSCard.Origin.aiSuggested.rawValue,
                        status: SRSCard.Status.proposed.rawValue,
                        stability: 0,
                        difficulty: 0,
                        dueDate: nil,
                        reviewCount: 0,
                        lapses: 0,
                        lastReviewedAt: nil
                    )
                }

            try await store.saveReport(
                WeeklyReportRecord(
                    id: nil,
                    generatedAt: now,
                    periodStart: start,
                    periodEnd: end,
                    summaryJSON: contentJSON
                ),
                proposedCards: cards
            )

            if notify {
                await Self.sendNotification(cardCount: cards.count)
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    private static func stats(for logs: [TranslationLog]) -> WeeklyReportContent.Stats {
        let reading = logs.count { $0.direction == TranslationLog.Direction.reading.rawValue }
        let appCounts = Dictionary(grouping: logs.compactMap(\.sourceApp), by: { $0 })
            .mapValues(\.count)
        let topApps = appCounts.sorted { $0.value > $1.value }.prefix(3).map(\.key)
        return WeeklyReportContent.Stats(
            total: logs.count,
            reading: reading,
            writing: logs.count - reading,
            topApps: topApps
        )
    }

    private static func sendNotification(cardCount: Int) async {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else { return }

        let content = UNMutableNotificationContent()
        content.title = "今週の学習レポートができました"
        content.body = cardCount > 0
            ? "覚える価値の高い表現を\(cardCount)件提案しています。メニューバーのKiokuから開けます。"
            : "今週の振り返りができました。メニューバーのKiokuから開けます。"
        content.sound = .default

        try? await center.add(UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        ))
    }
}
