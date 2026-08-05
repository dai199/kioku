import AppKit
import SwiftUI

/// 設定ウィンドウ。メニューバーアプリのためSwiftUIのSettingsシーンではなく
/// 自前のNSWindowで管理し、ポップアップ等どこからでも開けるようにする。
@MainActor
final class SettingsWindowController {
    private let settings: AppSettings
    private var window: NSWindow?

    init(settings: AppSettings) {
        self.settings = settings
    }

    func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 460, height: 300),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Kioku 設定"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(settings: settings))
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @ObservedObject var settings: AppSettings

    private enum TestPhase {
        case idle
        case running
        case success(String)
        case failure(String)
    }

    @State private var testPhase: TestPhase = .idle

    var body: some View {
        Form {
            Section("Gemini API（BYOK）") {
                SecureField("APIキー", text: $settings.geminiAPIKey)
                TextField("翻訳モデル", text: $settings.translationModel)
                TextField("分析モデル（週次レポート用）", text: $settings.analysisModel)
                Link("APIキーを取得（Google AI Studio）",
                     destination: URL(string: "https://aistudio.google.com/apikey")!)
                // 上のキーとモデル設定を検証するボタンなので、必ずこのセクション内に置く。
                // 無ラベルの別セクションにすると直前のセクションの一部に見える
                connectionTest
            }
            Section {
                excludedApps
            } header: {
                Text("除外アプリ")
            } footer: {
                Text("これらのアプリではアイコンを表示せず、テキストを一切送信しません。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("復習") {
                Toggle("毎朝、期限が来たカードを通知する", isOn: $settings.isReviewReminderEnabled)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// APIキーとモデル設定が実際に通るかを確かめる。結果は右に並べて出す。
    private var connectionTest: some View {
        HStack(spacing: 12) {
            Button("接続テスト") { runTest() }
                .disabled(!settings.hasAPIKey || isRunning)
            switch testPhase {
            case .idle:
                EmptyView()
            case .running:
                ProgressView().controlSize(.small)
            case .success(let translation):
                Label(translation, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .lineLimit(1)
            case .failure(let message):
                Label(message, systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
    }

    /// 除外アプリの一覧と追加/削除。
    /// バンドルIDを手入力させると打ち間違いに気づけないので、
    /// 実際の.appを選ばせてIDを読み取る。
    private var excludedApps: some View {
        VStack(alignment: .leading, spacing: 6) {
            if settings.excludedAppBundleIDs.isEmpty {
                Text("除外アプリはありません。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ForEach(settings.excludedAppBundleIDs.sorted(), id: \.self) { bundleID in
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(Self.displayName(for: bundleID))
                            .font(.callout)
                        Text(bundleID)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Button {
                        settings.excludedAppBundleIDs.remove(bundleID)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("除外から外す")
                }
            }
            Button("アプリを追加…") { addExcludedApp() }
                .controlSize(.small)
        }
    }

    /// バンドルIDから表示名を引く。未インストールならIDをそのまま見せる。
    private static func displayName(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: bundleID
        ) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path)
    }

    private func addExcludedApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "除外に追加"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let bundleID = Bundle(url: url)?.bundleIdentifier else { continue }
            settings.excludedAppBundleIDs.insert(bundleID)
        }
    }

    private var isRunning: Bool {
        if case .running = testPhase { return true }
        return false
    }

    private func runTest() {
        testPhase = .running
        let engine = settings.makeEngine()
        Task { @MainActor in
            do {
                let result = try await engine.translate(TranslationRequest(
                    text: "Hello! This is a connection test.",
                    sourceLanguage: "en",
                    targetLanguage: "ja"
                ))
                testPhase = .success(result)
            } catch {
                testPhase = .failure(error.localizedDescription)
            }
        }
    }
}
