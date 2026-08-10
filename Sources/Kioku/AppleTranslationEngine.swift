import Foundation
import Translation

/// Apple純正のオンデバイス翻訳（macOS 26.4以降）。
///
/// 端末内で完結するので、**選択したテキストが外部に一切出ない**（SPEC §5）。
/// オフラインでも動き、API費用もかからない。無料枠の待ち時間とも無縁。
///
/// 代わりにプロンプトを渡す口がないため、方向指定（もっとカジュアルに）も
/// 「別の訳」も原理的に成立しない。`capabilities` で表明し、画面側が出し分ける。
///
/// ここでの `TranslationSession` はAppleのフレームワークの型。
/// 本アプリのポップアップ側は `PopupTranslationSession` に改名して衝突を避けている。
@available(macOS 26.4, *)
struct AppleTranslationEngine: TranslationEngine {
    /// プロンプトを持たないので、実装の版を入れる。
    /// 先頭のエンジン名でキャッシュキーをGeminiと分ける。
    let promptVersion = "apple/1"

    /// 原文を渡して訳を受け取るだけ。再生成も方向指定もできない
    let capabilities = EngineCapabilities.translateOnly

    func translate(_ request: TranslationRequest) async throws -> String {
        let source = Locale.Language(identifier: request.sourceLanguage)
        let target = Locale.Language(identifier: request.targetLanguage)

        switch await LanguageAvailability().status(from: source, to: target) {
        case .unsupported:
            throw AppleTranslationError.unsupportedPair(
                source: request.sourceLanguage, target: request.targetLanguage
            )
        case .installed, .supported:
            break
        @unknown default:
            break
        }

        // ポップアップは即応性が要るので lowLatency を選ぶ（生成時にしか指定できない）
        let session = TranslationSession(
            installedSource: source, target: target, preferredStrategy: .lowLatency
        )

        // 言語モデルが未ダウンロードなら要求する。
        //
        // 実測: ビューを介さず生成したセッションでは canRequestDownloads が false になる。
        // ダウンロードの確認UIは提示元のビューを必要とするらしく、この経路からは出せない。
        // その場合はユーザーにシステム設定で追加してもらうしかないので、
        // そう伝わるエラーにする（呼び出し側が設定への導線を出す）。
        if await session.isReady == false {
            guard session.canRequestDownloads else {
                throw AppleTranslationError.languageNotDownloaded(
                    source: request.sourceLanguage, target: request.targetLanguage
                )
            }
            try await session.prepareTranslation()
        }

        return try await session.translate(request.text).targetText
    }
}

/// Apple翻訳固有の失敗。原因ごとに次の一手が違うので分けて出す。
enum AppleTranslationError: LocalizedError {
    case unsupportedPair(source: String, target: String)
    case languageNotDownloaded(source: String, target: String)

    var errorDescription: String? {
        switch self {
        case .unsupportedPair(let source, let target):
            return "Apple翻訳は\(Self.name(source))→\(Self.name(target))に対応していません。"
        case .languageNotDownloaded(let source, let target):
            return "\(Self.name(source))→\(Self.name(target))の翻訳データが未ダウンロードです。"
                + "システム設定の「一般 > 言語と地域 > 翻訳言語」で追加してください。"
        }
    }

    /// 翻訳データが足りない言語ペア。
    /// 返ってきたら呼び出し側がダウンロードの導線を出す
    /// （文章で手順を説明するより、その場でダウンロードさせるほうが確実）。
    var missingLanguagePair: (source: String, target: String)? {
        if case .languageNotDownloaded(let source, let target) = self {
            return (source, target)
        }
        return nil
    }

    /// システム設定 > 一般 > 言語と地域（翻訳言語はこの中）。
    /// 識別子は /System/Library/ExtensionKit/Extensions/Localization.appex から確認したもの。
    static let languageSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.Localization-Settings.extension"
    )

    private static func name(_ code: String) -> String {
        switch code {
        case "ja": "日本語"
        case "en": "英語"
        default: code
        }
    }
}
