import AppKit
import Foundation
import GRDB

/// スクリーンショット撮影用の起動モード。
///
/// **実DBには一切触れない。** インメモリDBに見本データを入れて起動するので、
/// 撮った画像に実際の翻訳履歴が写らない。見た目も引数で固定でき、
/// システム設定を変えずにライト/ダークの両方を撮れる。
///
///     Kioku.app -KiokuDemo -KiokuAppearance dark
enum DemoMode {
    static var isEnabled: Bool {
        CommandLine.arguments.contains("-KiokuDemo")
    }

    /// 自プロセスの見た目だけを上書きする。システム設定も他アプリも変わらない。
    static func applyAppearanceOverride() {
        guard let index = CommandLine.arguments.firstIndex(of: "-KiokuAppearance"),
              let value = CommandLine.arguments[safe: index + 1]
        else { return }
        NSApplication.shared.appearance = NSAppearance(named: value == "dark" ? .darkAqua : .aqua)
    }

    /// 見本データを入れたインメモリDB。実DBの代わりにこれを使わせる。
    static func makeStore() throws -> DatabaseManager {
        let store = try DatabaseManager(dbQueue: DatabaseQueue())
        try seed(store)
        return store
    }

    private static func seed(_ store: DatabaseManager) throws {
        let now = Date()
        let day: TimeInterval = 24 * 3600

        try store.dbQueue.write { db in
            for (offset, sample) in samples.enumerated() {
                var log = TranslationLog(
                    id: nil,
                    createdAt: now - Double(offset) * 6 * 3600,
                    sourceText: sample.source,
                    translatedText: sample.translated,
                    sourceLang: sample.sourceLang,
                    targetLang: sample.sourceLang == "ja" ? "en" : "ja",
                    direction: sample.sourceLang == "ja" ? "writing" : "reading",
                    sourceApp: sample.app,
                    sourceURL: nil,
                    sourceTitle: sample.title
                )
                try log.insert(db)
            }

            var report = WeeklyReportRecord(
                id: nil, generatedAt: now - day, periodStart: now - 8 * day,
                periodEnd: now - day, summaryJSON: reportJSON
            )
            try report.insert(db)

            for card in proposedCards {
                var record = SRSCard(
                    id: nil, createdAt: now - day, logId: nil, reportId: report.id,
                    front: card.front, back: card.back, reason: card.reason,
                    origin: SRSCard.Origin.aiSuggested.rawValue,
                    status: SRSCard.Status.proposed.rawValue,
                    stability: 0, difficulty: 0, dueDate: nil,
                    reviewCount: 0, lapses: 0, lastReviewedAt: nil
                )
                try record.insert(db)
            }
            for card in activeCards {
                var record = SRSCard(
                    id: nil, createdAt: now - 10 * day, logId: nil, reportId: nil,
                    front: card.front, back: card.back, reason: nil,
                    origin: SRSCard.Origin.manual.rawValue,
                    status: SRSCard.Status.active.rawValue,
                    stability: 4, difficulty: 2.5, dueDate: now - 3600,
                    reviewCount: 2, lapses: 0, lastReviewedAt: now - 4 * day
                )
                try record.insert(db)
            }
        }
    }

    /// 撮影用の翻訳エンジン。定型の訳をそのまま返す。
    ///
    /// 実エンジンで撮ると、ネットワークとAPIキーの有無で結果が変わり、
    /// 同じ画面を撮り直しても絵が一致しない。撮影では訳の中身を固定したい。
    static let engine: TranslationEngine = StubEngine()

    private struct StubEngine: TranslationEngine {
        let promptVersion = "demo/1"
        let capabilities = EngineCapabilities.full

        func translate(_ request: TranslationRequest) async throws -> String {
            samples.first { $0.source == request.text }?.translated
                ?? "I'll check and get back to you."
        }

        func explain(_ request: ExplanationRequest) async throws -> String {
            "「折り返します」は、こちらから改めて連絡するという意味の定型表現です。\n"
                + "get back to you がほぼそのまま対応し、期限を約束しない点まで含めて重なります。"
        }
    }

    // MARK: - 見本の中身

    private struct Sample {
        let source: String
        let translated: String
        let sourceLang: String
        let app: String
        let title: String?
    }

    private struct Card {
        let front: String
        let back: String
        var reason: String?
    }

    private static let samples: [Sample] = [
        .init(source: "確認して折り返します。", translated: "I'll check and get back to you.",
              sourceLang: "ja", app: "Slack", title: "#general"),
        .init(source: "The build keeps failing on CI but passes locally.",
              translated: "ローカルでは通るのに、CIだとビルドが落ち続ける。",
              sourceLang: "en", app: "Safari", title: "GitHub Actions"),
        .init(source: "少し時間をいただけますか。", translated: "Could you give me a bit more time?",
              sourceLang: "ja", app: "メール", title: "Re: スケジュール"),
        .init(source: "This behavior is deprecated and will be removed.",
              translated: "この挙動は非推奨で、いずれ削除されます。",
              sourceLang: "en", app: "Safari", title: "API Reference"),
        .init(source: "先ほどの件、対応しておきました。",
              translated: "I've gone ahead and taken care of that.",
              sourceLang: "ja", app: "Slack", title: "#dev"),
        .init(source: "Let me know if anything looks off.",
              translated: "おかしいところがあれば教えてください。",
              sourceLang: "en", app: "Slack", title: "#dev"),
    ]

    private static let proposedCards: [Card] = [
        .init(front: "先回りして対応しておく", back: "I've gone ahead and …",
              reason: "業務連絡で頻出。「もう済ませてある」を一語で伝えられる"),
        .init(front: "念のため確認する", back: "just to be sure",
              reason: "確認の前置きとして自然。丁寧すぎず使いやすい"),
        .init(front: "おかしいところがあれば", back: "if anything looks off",
              reason: "レビュー依頼の定型。直訳しがちな箇所"),
    ]

    private static let activeCards: [Card] = [
        .init(front: "確認して折り返します", back: "I'll check and get back to you."),
        .init(front: "少し時間をいただけますか", back: "Could you give me a bit more time?"),
    ]

    private static let reportJSON = """
    {
      "stats": {"total": 6, "reading": 3, "writing": 3, "topApps": ["Slack", "Safari"]},
      "analysis": {
        "summary": "今週は依頼と確認のやり取りが中心でした。\
    「先回りして済ませておく」「念のため確認する」といった、\
    相手の手間を減らす言い回しを繰り返し探しています。\
    ここが定着すると、やり取りの往復が一段減るはずです。",
        "patterns": [
          {
            "title": "「〜しておく」の言い換え",
            "description": "先回りの行動を伝える言い方を毎回探し直しています。\
    I've gone ahead and … に寄せると一息で伝わります。",
            "examples": ["対応しておきました", "確認しておきます"]
          },
          {
            "title": "やわらかい依頼",
            "description": "Could you … / Would you mind … の使い分けで迷う場面が続いています。",
            "examples": ["少し時間をいただけますか"]
          }
        ],
        "cards": []
      }
    }
    """
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
