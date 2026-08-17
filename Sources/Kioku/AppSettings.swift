import Foundation

/// 翻訳に使うエンジン。
/// 週次分析は常にGeminiを使うので、ここの選択は「ポップアップの翻訳」だけに効く。
enum TranslationProvider: String, CaseIterable, Sendable, Identifiable {
    case gemini
    case appleOnDevice
    case appleIntelligence

    var id: String { rawValue }

    var label: String {
        switch self {
        case .gemini: "Gemini（クラウド）"
        case .appleOnDevice: "Apple 翻訳（端末内）"
        case .appleIntelligence: "Apple Intelligence（端末内）"
        }
    }

    var detail: String {
        switch self {
        case .gemini:
            return String(localized: "文脈に合わせた訳が得意。「別の訳」と方向指定も使える。APIキーが必要")
        case .appleOnDevice:
            // 文字列連結で組み立てると翻訳者が全体を見られないので1文にする
            return String(localized: """
                いちばん速く、端末内で完結。オフラインでも無料で使える。\
                訳を返すことに特化しているので、「別の訳」と方向指定は対象外
                """)
        case .appleIntelligence:
            return String(localized: """
                端末内で完結しながら「別の訳」と方向指定まで使える。無料。\
                仕上げにこだわる場面ではクラウドと読み比べるとよい
                """)
        }
    }

    /// この環境で選べるか。Apple翻訳の TranslationSession はmacOS 26.4以降。
    /// 動かない環境で選ばせて黙って失敗させない
    var isAvailable: Bool {
        switch self {
        case .gemini:
            return true
        case .appleOnDevice:
            if #available(macOS 26.4, *) { return true }
            return false
        case .appleIntelligence:
            // 端末が対応していてもApple Intelligenceが無効なら使えない。
            // 実際に使えるかは実行時にしか分からないので、ここでは型の可用性だけ見る
            if #available(macOS 26.0, *) { return true }
            return false
        }
    }
}

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
    private static let providerKey = "translationProvider"

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

    /// ポップアップの翻訳に使うエンジン（週次分析は常にGemini）
    @Published var translationProvider: TranslationProvider {
        didSet {
            UserDefaults.standard.set(translationProvider.rawValue, forKey: Self.providerKey)
        }
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
        // 保存値が今の環境で使えないエンジンなら（OSを戻した等）Geminiに落とす
        let storedProvider = UserDefaults.standard.string(forKey: Self.providerKey)
            .flatMap(TranslationProvider.init(rawValue:))
        translationProvider = (storedProvider?.isAvailable == true) ? storedProvider! : .gemini
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
        switch translationProvider {
        case .appleOnDevice:
            if #available(macOS 26.4, *) {
                return AppleTranslationEngine()
            }
            // 使えない環境ではGeminiに落とす（isAvailableで弾いているので通常来ない）
            return GeminiEngine(apiKey: geminiAPIKey, model: translationModel)
        case .appleIntelligence:
            if #available(macOS 26.0, *) {
                return FoundationModelsEngine()
            }
            return GeminiEngine(apiKey: geminiAPIKey, model: translationModel)
        case .gemini:
            return GeminiEngine(apiKey: geminiAPIKey, model: translationModel)
        }
    }
}
