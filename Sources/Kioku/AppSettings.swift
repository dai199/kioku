import Foundation

/// ユーザー設定。APIキーはキーチェーン、それ以外はUserDefaultsに保存する。
@MainActor
final class AppSettings: ObservableObject {
    static let defaultModel = "gemini-flash-lite-latest"
    static let defaultAnalysisModel = "gemini-flash-latest"
    private static let apiKeyAccount = "gemini-api-key"
    private static let modelKey = "translationModel"
    private static let analysisModelKey = "analysisModel"

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

    init() {
        geminiAPIKey = KeychainStore.read(account: Self.apiKeyAccount) ?? ""
        translationModel = UserDefaults.standard.string(forKey: Self.modelKey) ?? Self.defaultModel
        analysisModel = UserDefaults.standard.string(forKey: Self.analysisModelKey) ?? Self.defaultAnalysisModel
    }

    var hasAPIKey: Bool { !geminiAPIKey.isEmpty }

    func makeEngine() -> TranslationEngine {
        GeminiEngine(apiKey: geminiAPIKey, model: translationModel)
    }
}
