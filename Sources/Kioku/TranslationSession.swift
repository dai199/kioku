import Foundation

/// 訳をどう採用したか。品質評価（SPEC §12）の行動シグナルとして記録する。
/// `paste`は⌘Vを送っただけで反映を確認できていないため、
/// 採用率を測るときは`replace`と同列に扱わないこと。
enum AdoptionMethod: String, Sendable {
    case replace   // AX書き込みでの置換（反映を確認済み）
    case paste     // ペーストシミュレートでの置換（反映は未確認）
    case copy
}

/// ポップアップ1回分の翻訳の状態を持つ。「別の訳」の再生成にも対応する。
@MainActor
final class TranslationSession: ObservableObject {
    enum Phase {
        case loading
        case streaming(String)  // 逐次表示中の部分テキスト
        case done(String)
        case failed(message: String, missingAPIKey: Bool)
    }

    /// 「覚える」ボタンの状態。訳が変われば別のカードになるので、
    /// 再生成・方向反転のたびに未追加へ戻す。
    enum CardState: Sendable {
        case notAdded
        case added          // このセッションで追加した
        case alreadyExists  // 同じ表裏のカードが既にあった
    }

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var cardState: CardState = .notAdded

    let event: SelectionEvent
    private(set) var sourceLanguage: String
    private(set) var targetLanguage: String

    /// 既に提示した訳（再生成で避けるため保持）
    private var previousCandidates: [String] = []
    /// 提示した全候補（提示順）。選好シグナルとして記録する
    private var candidates: [String] = []
    private var adoptedIndex: Int?
    private var adoptedVia: AdoptionMethod?
    private var finalized = false
    private let engine: TranslationEngine
    private let store: DatabaseManager
    private let cache: TranslationCache?
    private var hasLoggedReading = false
    private var task: Task<Void, Never>?

    init(
        event: SelectionEvent,
        engine: TranslationEngine,
        store: DatabaseManager = .shared,
        cache: TranslationCache? = nil
    ) {
        self.event = event
        self.engine = engine
        self.store = store
        self.cache = cache
        let direction = LanguageDetector.direction(for: event.text)
        self.sourceLanguage = direction.source
        self.targetLanguage = direction.target
    }

    func start() {
        guard task == nil else { return }
        runTranslation()
    }

    /// 現在の訳を却下して別の訳を生成する。
    func regenerate() {
        guard case .done(let current) = phase else { return }
        previousCandidates.append(current)
        cardState = .notAdded
        runTranslation()
    }

    /// 表示中の訳を復習カードとして手動追加する（SPEC フェーズ1.5-3）。
    /// AI提案を待たずにその場でカード化できるようにして、習慣ループを強くする。
    func addCard(for translation: String) {
        guard cardState == .notAdded else { return }
        let content = CardContent.make(
            sourceText: event.text,
            translatedText: translation,
            sourceLang: sourceLanguage
        )
        let store = self.store
        Task { @MainActor in
            // ポップアップからは元ログのidを辿れないためlogIdはnil
            // （履歴画面から追加した場合は紐づく）
            let added = (try? await store.addManualCard(
                front: content.front, back: content.back, logId: nil
            )) ?? false
            cardState = added ? .added : .alreadyExists
        }
    }

    /// 翻訳方向を反転して翻訳し直す（自動判定が外れたとき用）。
    /// 方向が変わると候補の意味が変わるため、選好の記録はリセットする。
    func flipDirection() {
        task?.cancel()
        swap(&sourceLanguage, &targetLanguage)
        previousCandidates = []
        candidates = []
        adoptedIndex = nil
        adoptedVia = nil
        cardState = .notAdded
        runTranslation()
    }

    func cancel() {
        task?.cancel()
    }

    /// 訳を採用した（置き換え/コピーした）ときに呼ぶ。
    /// 選好シグナルとしてどの候補をどう採用したかを覚えておき、
    /// 日→英の場合は「元の日本語＋採用した英文」を学習ログにも残す。
    func recordAdoption(of translation: String, via method: AdoptionMethod) {
        adoptedIndex = candidates.firstIndex(of: translation)
        adoptedVia = method
        guard sourceLanguage == "ja" else { return }
        saveLog(translation: translation, direction: .writing)
    }

    /// セッション終了時（ポップアップが閉じる時）に選好シグナルを記録する。
    /// 採用しなかったセッションも再生成率の分母として必ず1回記録する。
    func finalize() {
        guard !finalized, !candidates.isEmpty else { return }
        finalized = true

        let candidatesJSON = (try? JSONEncoder().encode(candidates))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        let direction: TranslationLog.Direction = sourceLanguage == "ja" ? .writing : .reading
        let record = TranslationSessionRecord(
            id: nil,
            createdAt: Date(),
            direction: direction.rawValue,
            sourceLang: sourceLanguage,
            targetLang: targetLanguage,
            sourceText: event.text,
            candidatesJSON: candidatesJSON,
            adoptedIndex: adoptedIndex,
            adoptedVia: adoptedVia?.rawValue,
            regenerationCount: candidates.count - 1,
            sourceApp: event.appName,
            promptVersion: GeminiEngine.promptVersion
        )
        let store = self.store
        Task {
            try? await store.saveSession(record)
        }
    }

    private func saveLog(translation: String, direction: TranslationLog.Direction) {
        let log = TranslationLog(
            id: nil,
            createdAt: Date(),
            sourceText: event.text,
            translatedText: translation,
            sourceLang: sourceLanguage,
            targetLang: targetLanguage,
            direction: direction.rawValue,
            sourceApp: event.appName,
            sourceURL: event.documentURL,
            sourceTitle: event.windowTitle
        )
        let store = self.store
        Task {
            try? await store.save(log)
        }
    }

    private func runTranslation() {
        task?.cancel()

        // 初回のみキャッシュを見る（再生成はバリエーション目的なので対象外）
        if previousCandidates.isEmpty,
           let cached = cache?.lookup(text: event.text, source: sourceLanguage, target: targetLanguage) {
            phase = .done(cached)
            candidates.append(cached)
            logReadingIfNeeded(cached)
            return
        }

        phase = .loading
        task = Task { @MainActor in
            do {
                let stream = engine.translateStream(TranslationRequest(
                    text: event.text,
                    sourceLanguage: sourceLanguage,
                    targetLanguage: targetLanguage,
                    alternativesToAvoid: previousCandidates
                ))
                var accumulated = ""
                for try await piece in stream {
                    guard !Task.isCancelled else { return }
                    accumulated += piece
                    phase = .streaming(accumulated)
                }
                guard !Task.isCancelled else { return }

                let translated = accumulated.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !translated.isEmpty else { throw GeminiError.emptyResult }
                phase = .done(translated)
                candidates.append(translated)
                if previousCandidates.isEmpty {
                    cache?.store(translated, text: event.text, source: sourceLanguage, target: targetLanguage)
                }
                logReadingIfNeeded(translated)
            } catch GeminiError.missingAPIKey {
                phase = .failed(message: "Gemini APIキーが設定されていません。", missingAPIKey: true)
            } catch {
                guard !Task.isCancelled else { return }
                phase = .failed(message: error.localizedDescription, missingAPIKey: false)
            }
        }
    }

    /// 読解（英→日）は表示された時点で学習ログとして残す。
    /// 再生成しても初回のみ（同じ選択で二重に記録しない）。
    private func logReadingIfNeeded(_ translation: String) {
        guard sourceLanguage != "ja", !hasLoggedReading else { return }
        hasLoggedReading = true
        saveLog(translation: translation, direction: .reading)
    }
}
