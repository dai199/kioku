import AppKit
import GRDB
import SwiftUI

/// 翻訳履歴ウィンドウ。
@MainActor
final class HistoryWindowController {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 480),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "翻訳履歴"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: HistoryView(model: HistoryModel()))
            window.center()
            window.setFrameAutosaveName("KiokuHistoryWindow")
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

/// 履歴一覧の状態。DBを監視し、新しい翻訳が入ると自動で反映される。
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
    @StateObject var model: HistoryModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("原文・訳文・アプリ名で検索", text: $model.searchText)
                    .textFieldStyle(.plain)
            }
            .padding(10)
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
        .frame(minWidth: 480, minHeight: 360)
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
            Text(log.sourceText)
                .font(.callout)
                .lineLimit(2)
            Text(log.translatedText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            HStack(spacing: 6) {
                Text(log.sourceLang == "ja" ? "日 → 英" : "英 → 日")
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.quaternary, in: Capsule())
                if let app = log.sourceApp {
                    Text(app)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                if let title = log.sourceTitle, !title.isEmpty {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Spacer()
                Text(log.createdAt, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}
