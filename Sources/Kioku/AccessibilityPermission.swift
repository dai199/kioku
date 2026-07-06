import AppKit
import ApplicationServices
import Combine

/// Accessibility権限の状態を監視し、リクエスト・設定画面への誘導を行う。
/// 権限はTCCに「バンドルID＋コード署名」で記録されるため、
/// 権限の付与/剥奪はアプリ再起動なしでポーリングで検知する。
@MainActor
final class AccessibilityPermission: ObservableObject {
    @Published private(set) var isTrusted = AXIsProcessTrusted()

    private var timer: Timer?

    init() {
        let timer = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func refresh() {
        let trusted = AXIsProcessTrusted()
        if trusted != isTrusted {
            isTrusted = trusted
        }
    }

    /// システム標準の権限リクエストダイアログを表示する（初回のみ表示される）。
    func prompt() {
        // kAXTrustedCheckOptionPrompt はグローバル変数のためSwift 6の並行性チェックに
        // 引っかかる。値は固定文字列なので直接指定する。
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    /// システム設定の「プライバシーとセキュリティ > アクセシビリティ」を開く。
    func openSystemSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}
