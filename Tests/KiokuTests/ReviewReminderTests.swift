import Foundation
import Testing
@testable import Kioku

/// 復習リマインダーを鳴らすかの判定。
/// 30分ごとに走るので、「同じ日に二度鳴らさない」が崩れると
/// 一日じゅう30分おきに通知が飛ぶ。境界を固定しておく。
@Suite("復習リマインダーの発火判定")
struct ReviewReminderTests {
    /// 実行環境のタイムゾーンに左右されないよう固定する
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }()

    private func date(day: Int, hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(
            year: 2026, month: 8, day: day, hour: hour, minute: minute
        ))!
    }

    private func shouldNotify(now: Date, lastNotified: Date?) -> Bool {
        ReviewReminder.shouldNotify(
            now: now, lastNotified: lastNotified, calendar: calendar
        )
    }

    @Test("通知時刻より前は鳴らさない")
    func silentBeforeScheduledHour() {
        #expect(!shouldNotify(now: date(day: 5, hour: ReviewReminder.hour - 1, minute: 59),
                              lastNotified: nil))
    }

    @Test("通知時刻ちょうどで鳴る")
    func firesAtScheduledHour() {
        #expect(shouldNotify(now: date(day: 5, hour: ReviewReminder.hour), lastNotified: nil))
    }

    @Test("朝を逃しても、その日のうちなら1回鳴る")
    func catchesUpLaterInTheDay() {
        // 通知時刻にアプリが起動していなかったケース
        #expect(shouldNotify(now: date(day: 5, hour: 18), lastNotified: nil))
    }

    @Test("同じ日に通知済みなら鳴らさない")
    func silentAfterNotifyingToday() {
        #expect(!shouldNotify(
            now: date(day: 5, hour: 18),
            lastNotified: date(day: 5, hour: ReviewReminder.hour)
        ))
    }

    @Test("前日に通知していれば今日は鳴る")
    func firesAgainNextDay() {
        #expect(shouldNotify(
            now: date(day: 5, hour: ReviewReminder.hour),
            lastNotified: date(day: 4, hour: ReviewReminder.hour)
        ))
    }

    @Test("日付が変わった直後は、まだ通知時刻前なので鳴らさない")
    func silentJustAfterMidnight() {
        #expect(!shouldNotify(
            now: date(day: 5, hour: 0, minute: 30),
            lastNotified: date(day: 4, hour: ReviewReminder.hour)
        ))
    }
}
