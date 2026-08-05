import Foundation
import UserNotifications

/// 毎朝、期限が来た復習カードの枚数を知らせる（SPEC フェーズ1.5-7）。
/// 復習の最大の敵は「開くのを忘れること」なので、こちらから出向く。
///
/// OSのカレンダートリガーではなく自前の定期チェックにしているのは、
/// 通知本文に「今何枚あるか」を入れたいため。トリガー予約型は本文を
/// 予約時点で固定するので、当日の枚数を出せない。
@MainActor
final class ReviewReminder {
    /// 通知する時刻（時）。設定可能にするかは使ってみてから決める
    nonisolated static let hour = 8
    private static let lastNotifiedKey = "lastReviewReminderDate"
    private static let checkInterval: TimeInterval = 30 * 60

    private let settings: AppSettings
    private let store: DatabaseManager
    private var task: Task<Void, Never>?

    init(settings: AppSettings, store: DatabaseManager = .shared) {
        self.settings = settings
        self.store = store
    }

    /// 起動45秒後に1回チェックし、以降30分ごとに繰り返す。
    /// 通知時刻をまたいだ瞬間に出す必要はないので、この粒度で十分。
    func start() {
        guard task == nil else { return }
        task = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(45))
            while !Task.isCancelled {
                guard let self else { return }
                await self.notifyIfDue()
                try? await Task.sleep(for: .seconds(Self.checkInterval))
            }
        }
    }

    /// 「今この瞬間に鳴らしてよいか」だけを決める。
    /// 30分ごとに走るので、同じ日に二度鳴らさないことが要。
    /// 朝の通知時刻にアプリが起動していなかった場合は、その日のうちに気づけるよう
    /// 後からでも1回だけ鳴らす（時刻を過ぎていること、が条件であって
    /// 「ちょうどその時刻」ではない）。
    nonisolated static func shouldNotify(
        now: Date, lastNotified: Date?, calendar: Calendar = .current
    ) -> Bool {
        let today = calendar.startOfDay(for: now)
        guard let scheduled = calendar.date(byAdding: .hour, value: hour, to: today),
              now >= scheduled
        else { return false }
        guard let lastNotified else { return true }
        return !calendar.isDate(lastNotified, inSameDayAs: now)
    }

    private func notifyIfDue(now: Date = Date()) async {
        guard settings.isReviewReminderEnabled else { return }

        let calendar = Calendar.current
        guard Self.shouldNotify(
            now: now,
            lastNotified: UserDefaults.standard.object(forKey: Self.lastNotifiedKey) as? Date,
            calendar: calendar
        ) else { return }

        // 今日のぶんをやり終えている人を急かさない
        let today = calendar.startOfDay(for: now)
        let doneToday = (try? await store.reviewCount(since: today)) ?? 0
        let remaining = ReviewModel.dailyLimit - doneToday
        guard remaining > 0 else { return }

        let due = (try? await store.dueCardCount(asOf: now)) ?? 0
        guard due > 0 else { return }

        // 実際に今日出題される枚数を伝える（上限を超えて煽らない）
        await Self.send(count: min(due, remaining))
        UserDefaults.standard.set(now, forKey: Self.lastNotifiedKey)
    }

    private static func send(count: Int) async {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else { return }

        let content = UNMutableNotificationContent()
        content.title = "今日の復習"
        content.body = "期限が来たカードが\(count)枚あります。タップして始めます。"
        content.sound = .default
        // タップで復習画面を開く（NotificationRouter）
        content.userInfo = [NotificationRouter.sectionKey: MainSection.review.rawValue]

        try? await center.add(UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        ))
    }
}
