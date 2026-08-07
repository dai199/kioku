import AppKit
import ServiceManagement

/// ログイン時の自動起動（SPEC フェーズ1.5-11）。
///
/// メニューバー常駐アプリは、起動していなければ何もできない。選択検知も
/// 復習リマインダーも週次レポートの自動生成も全部止まるので、
/// 再起動のたびに手で起動させるのは事実上「使えない日」を作ることになる。
///
/// 状態はアプリの外（システム設定）でも変わるため、保持せず毎回OSに問い合わせる。
@MainActor
final class LoginItem: ObservableObject {
    /// 登録済みで有効か
    @Published private(set) var isEnabled = false
    /// ユーザーの承認待ち（システム設定でオフにされた場合など）。
    /// この状態はアプリ側から解除できないので、設定へ誘導するしかない
    @Published private(set) var requiresApproval = false
    /// 直近の登録/解除の失敗理由
    @Published private(set) var lastError: String?

    /// システム設定 > 一般 > ログイン項目。
    /// 識別子は /System/Library/ExtensionKit/Extensions/LoginItems.appex から確認したもの。
    static let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
    )

    init() {
        refresh()
    }

    func refresh() {
        switch SMAppService.mainApp.status {
        case .enabled:
            isEnabled = true
            requiresApproval = false
        case .requiresApproval:
            isEnabled = false
            requiresApproval = true
        case .notRegistered, .notFound:
            isEnabled = false
            requiresApproval = false
        @unknown default:
            isEnabled = false
            requiresApproval = false
        }
    }

    func setEnabled(_ enabled: Bool) {
        lastError = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            lastError = error.localizedDescription
        }
        // 成否に関わらずOSの状態を正とする
        refresh()
    }

    func openSettings() {
        guard let url = Self.settingsURL else { return }
        NSWorkspace.shared.open(url)
    }
}
