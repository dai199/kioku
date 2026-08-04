import Foundation
import Testing
@testable import Kioku

/// SM-2系スケジューラの挙動。
/// 本格FSRSへ差し替える際、ここが「差し替え前後で何が変わったか」の基準になる。
@Suite("復習スケジューラ")
struct ReviewSchedulerTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let day: TimeInterval = 24 * 3600

    @Test("新規カードに『まあまあ』: 翌日に出し直し、易しさ係数は既定の2.5")
    func goodOnNewCard() {
        let outcome = ReviewScheduler.review(card: makeCard(), rating: .good, now: now)
        #expect(outcome.stability == 1)
        #expect(isClose(outcome.difficulty, 2.5))
        #expect(outcome.dueDate == now.addingTimeInterval(day))
        #expect(!outcome.isLapse)
    }

    @Test("新規カードに『余裕』: 4日後まで飛ばし、易しさ係数を上げる")
    func easyOnNewCard() {
        let outcome = ReviewScheduler.review(card: makeCard(), rating: .easy, now: now)
        #expect(outcome.stability == 4)
        #expect(isClose(outcome.difficulty, 2.65))
        #expect(outcome.dueDate == now.addingTimeInterval(4 * day))
        #expect(!outcome.isLapse)
    }

    @Test("『ダメ』: 間隔をリセットし、10分後に同セッションで再出題する")
    func againResetsInterval() {
        let card = makeCard(stability: 30, difficulty: 2.5, reviewCount: 3)
        let outcome = ReviewScheduler.review(card: card, rating: .again, now: now)
        #expect(outcome.stability == 0)
        #expect(isClose(outcome.difficulty, 2.3))
        #expect(outcome.dueDate == now.addingTimeInterval(10 * 60))
    }

    @Test("『ダメ』が失敗（lapse）に数えられるのは復習済みカードだけ")
    func lapseOnlyCountsForReviewedCards() {
        // 初回の「ダメ」は、まだ覚えていないだけなので失敗に数えない
        #expect(!ReviewScheduler.review(
            card: makeCard(reviewCount: 0), rating: .again, now: now
        ).isLapse)
        #expect(ReviewScheduler.review(
            card: makeCard(reviewCount: 1), rating: .again, now: now
        ).isLapse)
    }

    @Test("易しさ係数には下限1.3がある")
    func difficultyHasFloor() {
        let card = makeCard(stability: 10, difficulty: 1.4, reviewCount: 2)
        let outcome = ReviewScheduler.review(card: card, rating: .again, now: now)
        #expect(isClose(outcome.difficulty, 1.3))
    }

    @Test("易しさ係数には上限3.0がある")
    func difficultyHasCeiling() {
        let card = makeCard(stability: 10, difficulty: 2.95, reviewCount: 2)
        let outcome = ReviewScheduler.review(card: card, rating: .easy, now: now)
        #expect(isClose(outcome.difficulty, 3.0))
    }

    @Test("間隔は365日で頭打ちになる", arguments: [ReviewRating.good, .easy])
    func intervalIsCappedAtOneYear(rating: ReviewRating) {
        let card = makeCard(stability: 300, difficulty: 2.5, reviewCount: 5)
        let outcome = ReviewScheduler.review(card: card, rating: rating, now: now)
        #expect(outcome.stability == 365)
        #expect(outcome.dueDate == now.addingTimeInterval(365 * day))
    }

    @Test("『まあまあ』を重ねると間隔が易しさ係数の分だけ伸びる")
    func goodGrowsIntervalByEase() {
        let card = makeCard(stability: 10, difficulty: 2.0, reviewCount: 2)
        let outcome = ReviewScheduler.review(card: card, rating: .good, now: now)
        #expect(isClose(outcome.stability, 20))
        #expect(isClose(outcome.difficulty, 2.0)) // 「まあまあ」は係数を動かさない
    }
}

private func makeCard(
    stability: Double = 0,
    difficulty: Double = 0,
    reviewCount: Int = 0
) -> SRSCard {
    SRSCard(
        id: 1,
        createdAt: Date(timeIntervalSince1970: 0),
        logId: nil,
        reportId: nil,
        front: "確認します",
        back: "Let me check.",
        reason: nil,
        origin: SRSCard.Origin.aiSuggested.rawValue,
        status: SRSCard.Status.active.rawValue,
        stability: stability,
        difficulty: difficulty,
        dueDate: nil,
        reviewCount: reviewCount,
        lapses: 0,
        lastReviewedAt: nil
    )
}

/// 浮動小数の比較。0.15刻みの加算などで誤差が出るため直接比較は避ける。
private func isClose(_ actual: Double, _ expected: Double) -> Bool {
    abs(actual - expected) < 1e-9
}
