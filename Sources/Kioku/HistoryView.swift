import AppKit
import GRDB
import SwiftUI

/// 履歴一覧の状態。DBを監視し、新しい翻訳が入ると自動で反映される。
/// メインウィンドウが保持し、画面を切り替えても監視は張りっぱなしにする。
@MainActor
final class HistoryModel: ObservableObject {
    @Published private(set) var logs: [TranslationLog] = []
    @Published var searchText = ""

    private var cancellable: AnyDatabaseCancellable?

    func startObserving() {
        guard cancellable == nil else { return }
        let observation = ValueObservation.tracking { db in
            try TranslationLog
                .order(Column("createdAt").desc)
                .limit(500)
                .fetchAll(db)
        }
        cancellable = observation.start(
            in: DatabaseManager.shared.dbQueue,
            onError: { error in
                NSLog("履歴の監視に失敗: \(error)")
            },
            onChange: { logs in
                Task { @MainActor [weak self] in
                    self?.logs = logs
                }
            }
        )
    }

    var filteredLogs: [TranslationLog] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return logs }
        return logs.filter {
            $0.sourceText.localizedCaseInsensitiveContains(query)
                || $0.translatedText.localizedCaseInsensitiveContains(query)
                || ($0.sourceApp?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    func delete(_ log: TranslationLog) {
        guard let id = log.id else { return }
        Task {
            try? await DatabaseManager.shared.delete(id: id)
        }
    }
}

struct HistoryView: View {
    @ObservedObject var model: HistoryModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("原文・訳文・アプリ名で検索", text: $model.searchText)
                    .textFieldStyle(.plain)
            }
            .padding(12)
            Divider()

            if model.filteredLogs.isEmpty {
                ContentUnavailableView(
                    model.logs.isEmpty ? "まだ翻訳履歴がありません" : "検索結果なし",
                    systemImage: "clock",
                    description: Text(model.logs.isEmpty
                        ? "テキストを選択して翻訳すると、ここに記録されます。"
                        : "別のキーワードを試してください。")
                )
            } else {
                List(model.filteredLogs) { log in
                    HistoryRow(log: log)
                        .contextMenu {
                            Button("原文をコピー") { copy(log.sourceText) }
                            Button("訳文をコピー") { copy(log.translatedText) }
                            Divider()
                            Button("削除", role: .destructive) { model.delete(log) }
                        }
                }
                .listStyle(.inset)
            }
        }
        .onAppear { model.startObserving() }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

private struct HistoryRow: View {
    let log: TranslationLog

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // 文脈層: 原文・訳文とも callout（DESIGN.md）
            Text(log.sourceText)
                .font(.callout)
                .lineLimit(2)
            Text(log.translatedText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            // メタ層: caption2 / tertiary
            HStack(spacing: 6) {
                DirectionBadge(sourceLang: log.sourceLang)
                if let app = log.sourceApp {
                    Text(app)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if let title = log.sourceTitle, !title.isEmpty {
                    Text(title)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Spacer()
                Text(log.createdAt, format: .relative(presentation: .named))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}
