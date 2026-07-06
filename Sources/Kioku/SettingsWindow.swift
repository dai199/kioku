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
            }
            Section {
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
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
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
