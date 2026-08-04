import Foundation
import GRDB

/// 翻訳ログ1件。SPECのデータモデルに対応する。
struct TranslationLog: Codable, Identifiable, Sendable,
                       FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "translationLog"

    enum Direction: String, Codable, Sendable {
        case reading   // 英→日 読解支援
        case writing   // 日→英 ライティング支援（採用した訳）
    }

    var id: Int64?
    var createdAt: Date
    var sourceText: String
    var translatedText: String
    var sourceLang: String
    var targetLang: String
    var direction: String
    var sourceApp: String?
    var sourceURL: String?
    var sourceTitle: String?

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

/// SRSカード。AIの週次提案（proposed）を承認するとactiveになり復習キューに入る。
struct SRSCard: Codable, Identifiable, Sendable,
                FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "srsCard"

    enum Status: String, Codable, Sendable {
        case proposed   // AIが提案、未承認
        case active     // 承認済み・復習対象
        case rejected   // 却下
    }

    enum Origin: String, Codable, Sendable {
        case aiSuggested = "ai_suggested"
        case manual
    }

    var id: Int64?
    var createdAt: Date
    var logId: Int64?
    /// 提案元の週次レポート（手動追加カードはnil）
    var reportId: Int64?
    var front: String   // 日本語（意味・言いたいこと）
    var back: String    // 英文
    var reason: String? // AIの選定理由
    var origin: String
    var status: String
    // FSRS系の状態（復習画面＝フェーズ1項目7で使用）
    var stability: Double
    var difficulty: Double
    var dueDate: Date?
    var reviewCount: Int
    var lapses: Int
    var lastReviewedAt: Date?

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

/// 復習1回の記録。
struct ReviewLogRecord: Codable, Identifiable, Sendable,
                        FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "reviewLog"

    var id: Int64?
    var cardId: Int64
    var reviewedAt: Date
    var rating: String  // again | good | easy

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

/// 翻訳ポップアップ1回分の選好シグナル。
/// スタイル適応（SPEC §11）と品質評価（§12）の学習データになる。
/// 採用に至らなかったセッションも再生成率の分母として記録する。
struct TranslationSessionRecord: Codable, Identifiable, Sendable,
                                 FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "translationSession"

    var id: Int64?
    var createdAt: Date
    var direction: String
    var sourceLang: String
    var targetLang: String
    var sourceText: String
    /// 提示した全候補（提示順）のJSON配列
    var candidatesJSON: String
    /// 採用した候補のインデックス（未採用ならnil）
    var adoptedIndex: Int?
    /// 採用方法: replace | copy（未採用ならnil）
    var adoptedVia: String?
    var regenerationCount: Int
    var sourceApp: String?
    /// 生成に使ったプロンプトのバージョン（§12: どの変更が効いたか追跡する）
    var promptVersion: String?

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

/// 週次レポート。summaryJSONにWeeklyReportContentを格納する。
struct WeeklyReportRecord: Codable, Identifiable, Sendable,
                           FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "weeklyReport"

    var id: Int64?
    var generatedAt: Date
    var periodStart: Date
    var periodEnd: Date
    var summaryJSON: String

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

/// ローカルSQLite（ローカルファースト）。将来のクラウド同期はこの上に載せる。
final class DatabaseManager: Sendable {
    static let shared = DatabaseManager()

    let dbQueue: DatabaseQueue

    private init() {
        let directory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Kioku", isDirectory: true)
        // アプリサポートディレクトリの作成とマイグレーションが失敗するのは
        // ディスク異常などの致命的状況のみなので、MVPではクラッシュを許容する
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        dbQueue = try! DatabaseQueue(path: directory.appendingPathComponent("kioku.sqlite").path)
        try! Self.migrator.migrate(dbQueue)
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: TranslationLog.databaseTableName) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("createdAt", .datetime).notNull().indexed()
                t.column("sourceText", .text).notNull()
                t.column("translatedText", .text).notNull()
                t.column("sourceLang", .text).notNull()
                t.column("targetLang", .text).notNull()
                t.column("direction", .text).notNull()
                t.column("sourceApp", .text)
                t.column("sourceURL", .text)
                t.column("sourceTitle", .text)
            }
        }
        migrator.registerMigration("v2") { db in
            try db.create(table: SRSCard.databaseTableName) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("createdAt", .datetime).notNull()
                t.column("logId", .integer)
                    .references(TranslationLog.databaseTableName, onDelete: .setNull)
                t.column("front", .text).notNull()
                t.column("back", .text).notNull()
                t.column("reason", .text)
                t.column("origin", .text).notNull()
                t.column("status", .text).notNull().indexed()
                t.column("stability", .double).notNull().defaults(to: 0)
                t.column("difficulty", .double).notNull().defaults(to: 0)
                t.column("dueDate", .datetime).indexed()
                t.column("reviewCount", .integer).notNull().defaults(to: 0)
                t.column("lapses", .integer).notNull().defaults(to: 0)
                t.column("lastReviewedAt", .datetime)
            }
            try db.create(table: ReviewLogRecord.databaseTableName) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("cardId", .integer).notNull()
                    .references(SRSCard.databaseTableName, onDelete: .cascade)
                t.column("reviewedAt", .datetime).notNull()
                t.column("rating", .text).notNull()
            }
            try db.create(table: WeeklyReportRecord.databaseTableName) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("generatedAt", .datetime).notNull().indexed()
                t.column("periodStart", .datetime).notNull()
                t.column("periodEnd", .datetime).notNull()
                t.column("summaryJSON", .text).notNull()
            }
        }
        migrator.registerMigration("v3") { db in
            try db.create(table: TranslationSessionRecord.databaseTableName) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("createdAt", .datetime).notNull().indexed()
                t.column("direction", .text).notNull()
                t.column("sourceLang", .text).notNull()
                t.column("targetLang", .text).notNull()
                t.column("sourceText", .text).notNull()
                t.column("candidatesJSON", .text).notNull()
                t.column("adoptedIndex", .integer)
                t.column("adoptedVia", .text)
                t.column("regenerationCount", .integer).notNull()
                t.column("sourceApp", .text)
                t.column("promptVersion", .text)
            }
        }
        migrator.registerMigration("v4") { db in
            // カードを提案元のレポートに紐づける（過去レポートを開いたとき、
            // その週に提案されたカードだけを出せるようにする）
            try db.alter(table: SRSCard.databaseTableName) { t in
                t.add(column: "reportId", .integer)
                    .references(WeeklyReportRecord.databaseTableName, onDelete: .setNull)
            }
            try db.create(
                index: "srsCard_on_reportId",
                on: SRSCard.databaseTableName,
                columns: ["reportId"]
            )
            // 既存カードは生成時刻がいちばん近いレポートに割り当てる
            // （カードはレポートと同じトランザクションで作られるため実質同時刻）。
            // 外側の列はサブクエリのWHEREでしか参照できないので、
            // 「直前のレポート」→「直後のレポート」の2段で埋める
            let card = SRSCard.databaseTableName
            let report = WeeklyReportRecord.databaseTableName
            let aiSuggested = SRSCard.Origin.aiSuggested.rawValue
            try db.execute(sql: """
                UPDATE \(card) SET reportId = (
                    SELECT w.id FROM \(report) w
                    WHERE julianday(w.generatedAt) <= julianday(\(card).createdAt) + 0.0001
                    ORDER BY w.generatedAt DESC
                    LIMIT 1
                )
                WHERE origin = '\(aiSuggested)'
                """)
            try db.execute(sql: """
                UPDATE \(card) SET reportId = (
                    SELECT w.id FROM \(report) w
                    WHERE julianday(w.generatedAt) > julianday(\(card).createdAt)
                    ORDER BY w.generatedAt ASC
                    LIMIT 1
                )
                WHERE reportId IS NULL AND origin = '\(aiSuggested)'
                """)
        }
        return migrator
    }

    func save(_ log: TranslationLog) async throws {
        try await dbQueue.write { db in
            var log = log
            try log.insert(db)
        }
    }

    func delete(id: Int64) async throws {
        _ = try await dbQueue.write { db in
            try TranslationLog.deleteOne(db, key: id)
        }
    }

    func saveSession(_ record: TranslationSessionRecord) async throws {
        try await dbQueue.write { db in
            var record = record
            try record.insert(db)
        }
    }

    // MARK: - 週次レポート / SRSカード

    func fetchLogs(from start: Date, to end: Date) async throws -> [TranslationLog] {
        try await dbQueue.read { db in
            try TranslationLog
                .filter(Column("createdAt") >= start && Column("createdAt") < end)
                .order(Column("createdAt").asc)
                .fetchAll(db)
        }
    }

    /// 最も古い翻訳ログの日時。初回レポートの対象期間の開始に使う。
    func oldestLogDate() async throws -> Date? {
        try await dbQueue.read { db in
            try TranslationLog.order(Column("createdAt").asc).fetchOne(db)?.createdAt
        }
    }

    func latestReport() async throws -> WeeklyReportRecord? {
        try await dbQueue.read { db in
            try WeeklyReportRecord.order(Column("generatedAt").desc).fetchOne(db)
        }
    }

    /// レポートと提案カードをまとめて保存する。カードは提案元のレポートに紐づける。
    func saveReport(_ report: WeeklyReportRecord, proposedCards: [SRSCard]) async throws {
        try await dbQueue.write { db in
            var report = report
            try report.insert(db)
            for card in proposedCards {
                var card = card
                card.reportId = report.id
                try card.insert(db)
            }
        }
    }

    /// 手動で「覚える」カードを追加する（SPEC フェーズ1.5-3）。
    /// AI提案と違い承認の段階を挟まないので、はじめからactive・当日期限で作る。
    /// 同じ表裏のカードが既にあれば追加しない（履歴とポップアップの二重追加を防ぐ。
    /// 却下済みのカードは「もう要らない」の意思表示なので重複判定に含めない）。
    /// - Returns: 追加したらtrue、既にあればfalse
    @discardableResult
    func addManualCard(
        front: String, back: String, logId: Int64?, now: Date = Date()
    ) async throws -> Bool {
        try await dbQueue.write { db in
            let duplicates = try SRSCard
                .filter(Column("front") == front && Column("back") == back)
                .filter(Column("status") != SRSCard.Status.rejected.rawValue)
                .fetchCount(db)
            guard duplicates == 0 else { return false }

            var card = SRSCard(
                id: nil,
                createdAt: now,
                logId: logId,
                reportId: nil,
                front: front,
                back: back,
                reason: nil,
                origin: SRSCard.Origin.manual.rawValue,
                status: SRSCard.Status.active.rawValue,
                stability: 0,
                difficulty: 0,
                dueDate: now,
                reviewCount: 0,
                lapses: 0,
                lastReviewedAt: nil
            )
            try card.insert(db)
            return true
        }
    }

    func setCardStatus(id: Int64, status: SRSCard.Status, dueDate: Date?) async throws {
        try await dbQueue.write { db in
            guard var card = try SRSCard.fetchOne(db, key: id) else { return }
            card.status = status.rawValue
            card.dueDate = dueDate
            try card.update(db)
        }
    }

    // MARK: - 復習（SRS）

    /// 出題期限が来ているアクティブなカードを取得する。
    func dueCards(asOf date: Date, limit: Int) async throws -> [SRSCard] {
        try await dbQueue.read { db in
            try SRSCard
                .filter(Column("status") == SRSCard.Status.active.rawValue)
                .filter(Column("dueDate") == nil || Column("dueDate") <= date)
                .order(Column("dueDate").asc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    /// 指定日時以降に行った復習の回数（1日の上限管理に使う）。
    func reviewCount(since date: Date) async throws -> Int {
        try await dbQueue.read { db in
            try ReviewLogRecord.filter(Column("reviewedAt") >= date).fetchCount(db)
        }
    }

    /// 復習結果を反映する（カード更新＋復習ログ追加を1トランザクションで）。
    func applyReview(
        card: SRSCard,
        rating: ReviewRating,
        outcome: ReviewScheduler.Outcome,
        at now: Date
    ) async throws {
        guard let cardId = card.id else { return }
        try await dbQueue.write { db in
            guard var stored = try SRSCard.fetchOne(db, key: cardId) else { return }
            stored.stability = outcome.stability
            stored.difficulty = outcome.difficulty
            stored.dueDate = outcome.dueDate
            stored.reviewCount += 1
            if outcome.isLapse {
                stored.lapses += 1
            }
            stored.lastReviewedAt = now
            try stored.update(db)

            var log = ReviewLogRecord(
                id: nil, cardId: cardId, reviewedAt: now, rating: rating.rawValue
            )
            try log.insert(db)
        }
    }
}
