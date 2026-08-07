import Foundation
import GRDB
import Testing
@testable import Kioku

/// 復習キューとカード追加の問い合わせ。
/// 「今日どのカードが出るか」を決める境界なので、ずれると
/// 出るべきカードが出ない／終わったカードが出続ける、という形で効く。
/// インメモリDBなので実データには触れない。
@Suite("DBの問い合わせ")
struct DatabaseStoreTests {
    private func makeStore() throws -> DatabaseManager {
        try DatabaseManager(dbQueue: DatabaseQueue())
    }

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var hour: TimeInterval { 3600 }

    @discardableResult
    private func insert(
        _ store: DatabaseManager,
        front: String = "確認します",
        back: String = "Let me check.",
        status: SRSCard.Status = .active,
        dueDate: Date?,
        reviewCount: Int = 0
    ) throws -> Int64 {
        try store.dbQueue.write { db in
            var card = SRSCard(
                id: nil, createdAt: now, logId: nil, reportId: nil,
                front: front, back: back, reason: nil,
                origin: SRSCard.Origin.manual.rawValue,
                status: status.rawValue,
                stability: 0, difficulty: 0, dueDate: dueDate,
                reviewCount: reviewCount, lapses: 0, lastReviewedAt: nil
            )
            try card.insert(db)
            return card.id!
        }
    }

    // MARK: - 出題対象

    @Test("期限が来ているカードだけを返す（期限ちょうどは含む）")
    func dueCardsRespectsDueDate() async throws {
        let store = try makeStore()
        let past = try insert(store, front: "過去", dueDate: now - hour)
        let exact = try insert(store, front: "ちょうど", dueDate: now)
        try insert(store, front: "未来", dueDate: now + hour)

        let due = try await store.dueCards(asOf: now, limit: 10)
        #expect(Set(due.map(\.id)) == Set([past, exact]))
    }

    @Test("期限が未設定（nil）のカードも出題対象にする")
    func dueCardsIncludesNilDueDate() async throws {
        let store = try makeStore()
        let id = try insert(store, dueDate: nil)
        let due = try await store.dueCards(asOf: now, limit: 10)
        #expect(due.map(\.id) == [id])
    }

    @Test("未承認・却下のカードは出題しない", arguments: [SRSCard.Status.proposed, .rejected])
    func dueCardsOnlyActive(status: SRSCard.Status) async throws {
        let store = try makeStore()
        try insert(store, status: status, dueDate: now - hour)
        let due = try await store.dueCards(asOf: now, limit: 10)
        #expect(due.isEmpty)
    }

    @Test("limitで打ち切る（期限が古い順）")
    func dueCardsAppliesLimit() async throws {
        let store = try makeStore()
        let oldest = try insert(store, front: "最古", dueDate: now - 3 * hour)
        let middle = try insert(store, front: "中間", dueDate: now - 2 * hour)
        try insert(store, front: "直近", dueDate: now - hour)

        let due = try await store.dueCards(asOf: now, limit: 2)
        #expect(due.map(\.id) == [oldest, middle])
    }

    @Test("期限到来の枚数は出題対象と一致する")
    func dueCardCountMatches() async throws {
        let store = try makeStore()
        try insert(store, front: "1", dueDate: now - hour)
        try insert(store, front: "2", dueDate: nil)
        try insert(store, front: "3", dueDate: now + hour)
        try insert(store, front: "4", status: .proposed, dueDate: now - hour)

        let count = try await store.dueCardCount(asOf: now)
        #expect(count == 2)
    }

    // MARK: - 手動カード追加

    @Test("手動追加はactive・当日期限なので、すぐ出題対象になる")
    func manualCardIsImmediatelyDue() async throws {
        let store = try makeStore()
        let added = try await store.addManualCard(
            front: "確認します", back: "Let me check.", logId: nil, now: now
        )
        #expect(added)
        let due = try await store.dueCards(asOf: now, limit: 10)
        #expect(due.count == 1)
        #expect(due.first?.origin == SRSCard.Origin.manual.rawValue)
    }

    @Test("同じ表裏は二重に追加しない")
    func manualCardRejectsDuplicate() async throws {
        let store = try makeStore()
        _ = try await store.addManualCard(
            front: "確認します", back: "Let me check.", logId: nil, now: now
        )
        let second = try await store.addManualCard(
            front: "確認します", back: "Let me check.", logId: nil, now: now
        )
        #expect(second == false)
        let count = try await store.dueCardCount(asOf: now)
        #expect(count == 1)
    }

    @Test("却下済みのカードは重複判定に含めない（もう一度カード化できる）")
    func rejectedCardDoesNotBlockReAdding() async throws {
        let store = try makeStore()
        try insert(store, front: "確認します", back: "Let me check.", status: .rejected, dueDate: nil)
        let added = try await store.addManualCard(
            front: "確認します", back: "Let me check.", logId: nil, now: now
        )
        #expect(added)
    }

    // MARK: - 復習の反映

    @Test("復習するとカードが更新され、復習ログが1件増える")
    func applyReviewUpdatesCardAndLog() async throws {
        let store = try makeStore()
        let id = try insert(store, dueDate: now - hour)
        let card = try await store.dueCards(asOf: now, limit: 1)[0]
        let outcome = ReviewScheduler.review(card: card, rating: .good, now: now)

        try await store.applyReview(card: card, rating: .good, outcome: outcome, at: now)

        let updated = try await store.dbQueue.read { try SRSCard.fetchOne($0, key: id) }
        #expect(updated?.reviewCount == 1)
        #expect(updated?.dueDate == outcome.dueDate)
        #expect(updated?.lastReviewedAt == now)
        #expect(updated?.lapses == 0)
        let reviews = try await store.reviewCount(since: now - hour)
        #expect(reviews == 1)
    }

    @Test("失敗（lapse）のときだけlapsesが増える")
    func applyReviewCountsLapses() async throws {
        let store = try makeStore()
        // 復習済みカードの「ダメ」はlapse
        let id = try insert(store, dueDate: now - hour, reviewCount: 3)
        let card = try await store.dueCards(asOf: now, limit: 1)[0]
        let outcome = ReviewScheduler.review(card: card, rating: .again, now: now)
        #expect(outcome.isLapse)

        try await store.applyReview(card: card, rating: .again, outcome: outcome, at: now)
        let updated = try await store.dbQueue.read { try SRSCard.fetchOne($0, key: id) }
        #expect(updated?.lapses == 1)
    }

    @Test("復習回数は指定日時以降だけを数える")
    func reviewCountIsBoundedByDate() async throws {
        let store = try makeStore()
        let id = try insert(store, dueDate: now - hour)
        let card = try await store.dueCards(asOf: now, limit: 1)[0]
        let outcome = ReviewScheduler.review(card: card, rating: .good, now: now)
        try await store.applyReview(card: card, rating: .good, outcome: outcome, at: now)
        _ = id

        let before = try await store.reviewCount(since: now - hour)
        let after = try await store.reviewCount(since: now + hour)
        #expect(before == 1)
        #expect(after == 0)
    }

    // MARK: - レポート

    @Test("レポート保存時に、提案カードへレポートのidが入る")
    func saveReportLinksProposedCards() async throws {
        let store = try makeStore()
        let report = WeeklyReportRecord(
            id: nil, generatedAt: now, periodStart: now - 24 * hour, periodEnd: now,
            summaryJSON: "{}"
        )
        let card = SRSCard(
            id: nil, createdAt: now, logId: nil, reportId: nil,
            front: "確認します", back: "Let me check.", reason: nil,
            origin: SRSCard.Origin.aiSuggested.rawValue,
            status: SRSCard.Status.proposed.rawValue,
            stability: 0, difficulty: 0, dueDate: nil,
            reviewCount: 0, lapses: 0, lastReviewedAt: nil
        )
        try await store.saveReport(report, proposedCards: [card])

        let saved = try await store.dbQueue.read { db in
            try SRSCard.fetchAll(db)
        }
        let latest = try await store.latestReport()
        #expect(saved.count == 1)
        #expect(saved.first?.reportId == latest?.id)
    }

    @Test("最古のログ日時を返す（初回レポートの起点に使う）")
    func oldestLogDate() async throws {
        let store = try makeStore()
        let empty = try await store.oldestLogDate()
        #expect(empty == nil)

        for offset in [0, -48, -24] as [TimeInterval] {
            try await store.save(TranslationLog(
                id: nil, createdAt: now + offset * hour,
                sourceText: "確認します", translatedText: "Let me check.",
                sourceLang: "ja", targetLang: "en",
                direction: TranslationLog.Direction.writing.rawValue,
                sourceApp: nil, sourceURL: nil, sourceTitle: nil
            ))
        }
        let oldest = try await store.oldestLogDate()
        #expect(oldest == now - 48 * hour)
    }
}
