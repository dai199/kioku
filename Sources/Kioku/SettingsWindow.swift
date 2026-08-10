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
    /// 状態はシステム設定側でも変わるので、この画面を開くたびに問い合わせ直す
    @StateObject private var loginItem = LoginItem()

    /// 所要時間も持つ。キーを差し替えて押せば無料枠と有料枠の速度差が比べられる
    /// （無料枠は応答に15〜20秒かかることがある）。失敗時も、即座の拒否か
    /// タイムアウトかで原因が変わるので測る。
    private enum TestPhase {
        case idle
        case running
        case success(String, duration: TimeInterval)
        case failure(TestFailure)
    }

    private struct TestFailure {
        let message: String
        let duration: TimeInterval
        /// 翻訳データが足りない言語ペア。あればダウンロードの導線を出す
        let missingLanguages: (source: String, target: String)?
    }

    @State private var testPhase: TestPhase = .idle

    var body: some View {
        Form {
            Section {
                Picker("翻訳エンジン", selection: $settings.translationProvider) {
                    ForEach(TranslationProvider.allCases) { provider in
                        Text(provider.label)
                            .tag(provider)
                            // 動かない環境で選ばせて黙って失敗させない
                            .disabled(!provider.isAvailable)
                    }
                }
                Text(settings.translationProvider.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                // 選択中のエンジンをそのまま試す。Apple翻訳の初回は言語データの
                // ダウンロードが要ることがあるので、ポップアップより先にここで通しておける
                connectionTest
            } footer: {
                // 選択に関わらずAPIキーが要ることを明示する。
                // 「Apple翻訳にしたのにキーを求められる」と混乱するため
                Text("週次レポートの分析は、この選択に関わらず常にGeminiを使います。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Gemini API（BYOK）") {
                SecureField("APIキー", text: $settings.geminiAPIKey)
                TextField("翻訳モデル", text: $settings.translationModel)
                TextField("分析モデル（週次レポート用）", text: $settings.analysisModel)
                Link("APIキーを取得（Google AI Studio）",
                     destination: URL(string: "https://aistudio.google.com/apikey")!)
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
            Section("一般") {
                Toggle("ログイン時に起動する", isOn: Binding(
                    get: { loginItem.isEnabled },
                    set: { loginItem.setEnabled($0) }
                ))
                if loginItem.requiresApproval {
                    // この状態はアプリ側から解除できない。設定へ送るしかない
                    Text("システム設定で許可が必要です。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("「ログイン項目」を開く…") { loginItem.openSettings() }
                        .controlSize(.small)
                }
                if let error = loginItem.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        // システム設定で切り替えられている可能性があるので、開くたびに取り直す
        .onAppear { loginItem.refresh() }
    }

    /// 選択中のエンジンで実際に1文訳してみる。
    /// 失敗の理由は行内に押し込めないので、下に折り返して全文を出す
    /// （切り詰めると「どうすればいいか分からない」表示になる）。
    private var connectionTest: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Button("翻訳テスト") { runTest() }
                    // APIキーが要るのはGeminiのときだけ（Apple翻訳は端末内で完結する）
                    .disabled(
                        isRunning
                            || (settings.translationProvider == .gemini && !settings.hasAPIKey)
                    )
                switch testPhase {
                case .idle:
                    EmptyView()
                case .running:
                    ProgressView().controlSize(.small)
                case .success(let translation, let duration):
                    Label(translation, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .lineLimit(1)
                    elapsed(duration)
                case .failure(let failure):
                    Label("失敗", systemImage: "xmark.circle.fill")
                        .foregroundStyle(.red)
                    elapsed(failure.duration)
                }
                Spacer()
            }
            if case .failure(let failure) = testPhase {
                Text(failure.message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    // 折り返して必要なだけ縦に伸ばす（切り詰めない）
                    .fixedSize(horizontal: false, vertical: true)
                // 手順を文章で説明するより、その場でダウンロードさせるほうが確実。
                // 設定ウィンドウは通常のアクティブなウィンドウなので、
                // ポップアップと違ってダウンロード確認UIを出せる
                if let missing = failure.missingLanguages {
                    if #available(macOS 26.4, *) {
                        LanguageDownloadButton(
                            source: missing.source,
                            target: missing.target,
                            onFallback: openLanguageSettings
                        )
                    } else {
                        Button("「言語と地域」を開く…", action: openLanguageSettings)
                            .controlSize(.small)
                    }
                }
            }
        }
    }

    /// 所要時間。訳文が長くても押し出されないよう、優先度を上げて確保する
    /// （速度を見るための表示なので、これが消えては意味がない）。
    private func elapsed(_ duration: TimeInterval) -> some View {
        Text(String(format: "%.1f秒", duration))
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .layoutPriority(1)
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

    private func openLanguageSettings() {
        guard let url = AppleTranslationError.languageSettingsURL else { return }
        NSWorkspace.shared.open(url)
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
        let startedAt = Date()
        Task { @MainActor in
            do {
                let result = try await engine.translate(TranslationRequest(
                    text: "Hello! This is a connection test.",
                    sourceLanguage: "en",
                    targetLanguage: "ja"
                ))
                testPhase = .success(result, duration: Date().timeIntervalSince(startedAt))
            } catch {
                testPhase = .failure(TestFailure(
                    message: error.localizedDescription,
                    duration: Date().timeIntervalSince(startedAt),
                    missingLanguages: (error as? AppleTranslationError)?.missingLanguagePair
                ))
            }
        }
    }
}
