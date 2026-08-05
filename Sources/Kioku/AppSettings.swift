import Foundation

/// ユーザー設定。APIキーはキーチェーン、それ以外はUserDefaultsに保存する。
@MainActor
final class AppSettings: ObservableObject {
    static let defaultModel = "gemini-flash-lite-latest"
    static let defaultAnalysisModel = "gemini-flash-latest"
    private static let apiKeyAccount = "gemini-api-key"
    private static let modelKey = "translationModel"
    private static let analysisModelKey = "analysisModel"
    private static let excludedAppsKey = "excludedAppBundleIDs"
    private static let reviewReminderKey = "reviewReminderEnabled"

    /// 初回起動時にだけ入れる除外アプリ（SPEC §5）。
    /// パスワードマネージャーは翻訳したい場面がなく、事故ったときの被害が大きい。
    /// 「キーの有無」で初回を判定するので、ユーザーが消したものは復活しない。
    /// 手元にないアプリのバンドルIDを当て推量で並べても外れるだけなので、
    /// 確実なものだけを入れ、あとは設定画面から追加してもらう。
    static let defaultExcludedBundleIDs: Set<String> = [
        "com.apple.keychainaccess",   // キーチェーンアクセス
        "com.1password.1password",    // 1Password 8
        "com.agilebits.onepassword7", // 1Password 7
        "com.bitwarden.desktop",      // Bitwarden
        "org.keepassxc.keepassxc",    // KeePassXC
    ]

    @Published var geminiAPIKey: String {
        didSet {
            if geminiAPIKey.isEmpty {
                KeychainStore.delete(account: Self.apiKeyAccount)
            } else {
                KeychainStore.save(geminiAPIKey, account: Self.apiKeyAccount)
            }
        }
    }

    @Published var translationModel: String {
        didSet {
            UserDefaults.standard.set(translationModel, forKey: Self.modelKey)
        }
    }

    /// 週次分析用の上位モデル（SPECの二層構成）
    @Published var analysisModel: String {
        didSet {
            UserDefaults.standard.set(analysisModel, forKey: Self.analysisModelKey)
        }
    }

    /// アイコンを出さない＝テキストを一切送らないアプリ（SPEC §5）
    @Published var excludedAppBundleIDs: Set<String> {
        didSet { persistExcludedApps() }
    }

    /// 毎朝の復習リマインダーを出すか
    @Published var isReviewReminderEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isReviewReminderEnabled, forKey: Self.reviewReminderKey)
        }
    }

    init() {
        geminiAPIKey = KeychainStore.read(account: Self.apiKeyAccount) ?? ""
        translationModel = UserDefaults.standard.string(forKey: Self.modelKey) ?? Self.defaultModel
        analysisModel = UserDefaults.standard.string(forKey: Self.analysisModelKey) ?? Self.defaultAnalysisModel
        let storedExclusions = UserDefaults.standard.stringArray(forKey: Self.excludedAppsKey)
        excludedAppBundleIDs = storedExclusions.map(Set.init) ?? Self.defaultExcludedBundleIDs
        // 未設定なら既定値（初回起動）。以降はユーザーの編集が正
        isReviewReminderEnabled =
            UserDefaults.standard.object(forKey: Self.reviewReminderKey) as? Bool ?? true
        // 初期化中の代入ではdidSetが走らないので、初回だけ明示的に書き出す
        if storedExclusions == nil {
            persistExcludedApps()
        }
    }

    var hasAPIKey: Bool { !geminiAPIKey.isEmpty }

    /// 除外アプリでの選択か。ここがtrueならアイコンも出さず、翻訳もしない。
    func isExcluded(bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return excludedAppBundleIDs.contains(bundleID)
    }

    private func persistExcludedApps() {
        UserDefaults.standard.set(
            excludedAppBundleIDs.sorted(), forKey: Self.excludedAppsKey
        )
    }

    func makeEngine() -> TranslationEngine {
        GeminiEngine(apiKey: geminiAPIKey, model: translationModel)
    }
}
