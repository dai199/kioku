import AppKit
import GRDB
import SwiftUI

/// 週次レポートウィンドウ。
@MainActor
final class ReportWindowController {
    private let manager: ReportManager
    private var window: NSWindow?

    init(manager: ReportManager) {
        self.manager = manager
    }

    func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 560),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "週次レポート"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(
                rootView: ReportView(model: ReportModel(), manager: manager)
            )
            window.center()
            window.setFrameAutosaveName("KiokuReportWindow")
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

/// 最新レポートと提案中カードの状態。DB監視で自動更新される。
@MainActor
final class ReportModel: ObservableObject {
    @Published private(set) var report: WeeklyReportRecord?
    @Published private(set) var proposedCards: [SRSCard] = []

    private var reportCancellable: AnyDatabaseCancellable?
    private var cardsCancellable: AnyDatabaseCancellable?

    var reportContent: WeeklyReportContent? {
        guard let report else { return nil }
        return try? JSONDecoder().decode(
            WeeklyReportContent.self, from: Data(report.summaryJSON.utf8)
        )
    }

    func startObserving() {
        guard reportCancellable == nil else { return }
        reportCancellable = ValueObservation
            .tracking { db in
                try WeeklyReportRecord.order(Column("generatedAt").desc).fetchOne(db)
            }
            .start(
                in: DatabaseManager.shared.dbQueue,
                onError: { NSLog("レポート監視に失敗: \($0)") },
                onChange: { report in
                    Task { @MainActor [weak self] in self?.report = report }
                }
            )
        cardsCancellable = ValueObservation
            .tracking { db in
                try SRSCard
                    .filter(Column("status") == SRSCard.Status.proposed.rawValue)
                    .order(Column("createdAt").desc)
                    .fetchAll(db)
            }
            .start(
                in: DatabaseManager.shared.dbQueue,
                onError: { NSLog("カード監視に失敗: \($0)") },
                onChange: { cards in
                    Task { @MainActor [weak self] in self?.proposedCards = cards }
                }
            )
    }

    func approve(_ card: SRSCard) {
        guard let id = card.id else { return }
        Task {
            // 承認したカードは即日復習対象になる
            try? await DatabaseManager.shared.setCardStatus(id: id, status: .active, dueDate: Date())
        }
    }

    func reject(_ card: SRSCard) {
        guard let id = card.id else { return }
        Task {
            try? await DatabaseManager.shared.setCardStatus(id: id, status: .rejected, dueDate: nil)
        }
    }

    func approveAll() {
        for card in proposedCards {
            approve(card)
        }
    }
}

struct ReportView: View {
    @StateObject var model: ReportModel
    @ObservedObject var manager: ReportManager

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let content = model.reportContent {
                reportBody(content)
            } else {
                ContentUnavailableView(
                    "まだレポートがありません",
                    systemImage: "chart.line.text.clipboard",
                    description: Text("1週間分の翻訳ログが貯まると自動で生成されます。\n「今すぐ生成」で手動生成もできます。")
                )
            }
        }
        .onAppear { model.startObserving() }
        .frame(minWidth: 520, minHeight: 480)
    }

    private var header: some View {
        HStack {
            if let report = model.report {
                Text("\(report.periodStart, format: .dateTime.month().day()) 〜 \(report.periodEnd, format: .dateTime.month().day()) ・ 生成: \(report.generatedAt, format: .relative(presentation: .named))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            if manager.isGenerating {
                ProgressView().controlSize(.small)
                Text("分析中…").font(.caption).foregroundStyle(.secondary)
            } else {
                Button("今すぐ生成") {
                    Task { await manager.generate(notify: false) }
                }
                .controlSize(.small)
            }
        }
        .padding(10)
    }

    private func reportBody(_ content: WeeklyReportContent) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let error = manager.lastError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.red)
                }

                // 統計
                HStack(spacing: 16) {
                    statTile(value: content.stats.total, label: "翻訳")
                    statTile(value: content.stats.reading, label: "読解（英→日）")
                    statTile(value: content.stats.writing, label: "作文（日→英）")
                    if !content.stats.topApps.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("よく使った場所")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(content.stats.topApps.joined(separator: " / "))
                                .font(.callout)
                        }
                    }
                    Spacer()
                }

                // 総評
                Text(content.analysis.summary)
                    .font(.callout)

                // つまずきパターン
                if !content.analysis.patterns.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("今週のつまずきパターン")
                            .font(.headline)
                        ForEach(Array(content.analysis.patterns.enumerated()), id: \.offset) { index, pattern in
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(index + 1). \(pattern.title)")
                                    .font(.callout.weight(.semibold))
                                Text(pattern.description)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                if let examples = pattern.examples, !examples.isEmpty {
                                    ForEach(examples, id: \.self) { example in
                                        Text("・\(example)")
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                            .cardBox()
                        }
                    }
                }

                // カード候補
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("覚えるカード候補（\(model.proposedCards.count)）")
                            .font(.headline)
                        Spacer()
                        if model.proposedCards.count > 1 {
                            Button("すべて承認") { model.approveAll() }
                                .controlSize(.small)
                        }
                    }
                    if model.proposedCards.isEmpty {
                        Text("未承認の候補はありません。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.proposedCards) { card in
                        ProposedCardRow(
                            card: card,
                            onApprove: { model.approve(card) },
                            onReject: { model.reject(card) }
                        )
                    }
                }
            }
            .padding(14)
        }
    }

    private func statTile(value: Int, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.title3.weight(.semibold))
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ProposedCardRow: View {
    let card: SRSCard
    let onApprove: () -> Void
    let onReject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // 覚える対象の英文が主役、日本語は文脈（DESIGN.md）
            Text(card.front)
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(card.back)
                .font(.callout.weight(.medium))
            if let reason = card.reason, !reason.isEmpty {
                Text(reason)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            HStack {
                Spacer()
                Button("却下", role: .destructive, action: onReject)
                    .controlSize(.small)
                Button("承認", action: onApprove)
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
            }
        }
        .cardBox()
    }
}
