import Foundation
import GRDB
import Testing
@testable import Kioku

/// マイグレーション。
/// ここは唯一「壊れると実データが失われる」層で、しかもv4のように
/// SQLを直書きしたバックフィルを含む。静かに間違っていても気づけないので固定する。
/// すべてインメモリDBで動くので、実DB（アプリサポート配下）には触れない。
@Suite("DBマイグレーション")
struct DatabaseMigrationTests {
    @Test("空のDBに全マイグレーションが通り、必要なテーブルが揃う")
    func migratesFromEmpty() throws {
        let queue = try DatabaseQueue()
        try DatabaseManager.migrator.migrate(queue)

        let (missingTables, srsColumns, sessionColumns) = try queue.read { db in
            let missing = try ["translationLog", "srsCard", "reviewLog", "weeklyReport",
                               "translationSession"]
                .filter { try !db.tableExists($0) }
            return (
                missing,
                try db.columns(in: "srsCard").map(\.name),
                try db.columns(in: "translationSession").map(\.name)
            )
        }
        #expect(missingTables.isEmpty, "ないテーブル: \(missingTables)")
        // 後から足した列（v4 / v5）
        #expect(srsColumns.contains("reportId"))
        #expect(sessionColumns.contains("styleDirectionsJSON"))
    }

    @Test("二重に適用しても壊れない")
    func migratingTwiceIsSafe() throws {
        let queue = try DatabaseQueue()
        try DatabaseManager.migrator.migrate(queue)
        try DatabaseManager.migrator.migrate(queue)
        let exists = try queue.read { try $0.tableExists("srsCard") }
        #expect(exists)
    }

    @Test("v4: 既存のAI提案カードが、生成時刻の最も近いレポートに紐づく")
    func v4BackfillsReportID() throws {
        let queue = try DatabaseQueue()
        // v4より前の状態を作る（このときsrsCardにreportIdはまだない）
        try DatabaseManager.migrator.migrate(queue, upTo: "v3")
        try queue.write { db in
            try db.execute(sql: """
                INSERT INTO weeklyReport (id, generatedAt, periodStart, periodEnd, summaryJSON)
                VALUES
                  (1, '2026-07-01 00:00:00', '2026-06-24 00:00:00', '2026-07-01 00:00:00', '{}'),
                  (2, '2026-07-08 00:00:00', '2026-07-01 00:00:00', '2026-07-08 00:00:00', '{}')
                """)
            try db.execute(sql: """
                INSERT INTO srsCard
                  (id, createdAt, front, back, origin, status,
                   stability, difficulty, reviewCount, lapses)
                VALUES
                  (1, '2026-07-08 00:00:00', 'あ', 'A', 'ai_suggested', 'proposed', 0, 0, 0, 0),
                  (2, '2026-07-01 00:00:00', 'い', 'B', 'ai_suggested', 'proposed', 0, 0, 0, 0),
                  (3, '2026-07-08 00:00:00', 'う', 'C', 'manual', 'active', 0, 0, 0, 0)
                """)
        }

        try DatabaseManager.migrator.migrate(queue)

        let assigned = try queue.read { db in
            try Row.fetchAll(db, sql: "SELECT id, reportId FROM srsCard ORDER BY id")
                .map { ($0["id"] as Int64, $0["reportId"] as Int64?) }
        }
        #expect(assigned.first { $0.0 == 1 }?.1 == 2)   // 同時刻のレポートに付く
        #expect(assigned.first { $0.0 == 2 }?.1 == 1)
        // 手動追加カードはレポート由来ではないので触らない
        #expect(assigned.first { $0.0 == 3 }?.1 == nil)
    }

    @Test("v4: レポートが1件もなければ、カードは紐づかないまま壊れない")
    func v4WithoutAnyReport() throws {
        let queue = try DatabaseQueue()
        try DatabaseManager.migrator.migrate(queue, upTo: "v3")
        try queue.write { db in
            try db.execute(sql: """
                INSERT INTO srsCard
                  (id, createdAt, front, back, origin, status,
                   stability, difficulty, reviewCount, lapses)
                VALUES (1, '2026-07-08 00:00:00', 'あ', 'A', 'ai_suggested', 'proposed', 0, 0, 0, 0)
                """)
        }
        try DatabaseManager.migrator.migrate(queue)
        let reportID = try queue.read { db in
            try Int64.fetchOne(db, sql: "SELECT reportId FROM srsCard WHERE id = 1")
        }
        #expect(reportID == nil)
    }
}
