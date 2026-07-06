import AppKit
import SwiftUI

/// SRS復習ウィンドウ。開くたびに新しいセッションを開始する。
@MainActor
final class ReviewWindowController {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 420),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "復習"
            window.isReleasedWhenClosed = false
            window.center()
            window.setFrameAutosaveName("KiokuReviewWindow")
            self.window = window
        }
        // 開くたびにセッションを仕切り直す
        window?.contentView = NSHostingView(rootView: ReviewView(model: ReviewModel()))
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

/// 復習セッション1回分の状態。
@MainActor
final class ReviewModel: ObservableObject {
    /// 1日の復習上限（SPEC: 5分以内・20枚程度）
    static let dailyLimit = 20

    enum SessionState {
        case loading
        case empty          // 復習対象なし
        case limitReached   // 今日の上限に到達済み
        case reviewing
        case finished
    }

    @Published private(set) var state: SessionState = .loading
    @Published private(set) var current: SRSCard?
    @Published private(set) var isRevealed = false
    @Published private(set) var doneCount = 0
    private(set) var totalCount = 0

    private var queue: [SRSCard] = []

    func startSession() {
        Task { @MainActor in
            let now = Date()
            let startOfDay = Calendar.current.startOfDay(for: now)
            let doneToday = (try? await DatabaseManager.shared.reviewCount(since: startOfDay)) ?? 0
            let remaining = Self.dailyLimit - doneToday
            guard remaining > 0 else {
                state = .limitReached
                return
            }
            let cards = (try? await DatabaseManager.shared.dueCards(asOf: now, limit: remaining)) ?? []
            guard !cards.isEmpty else {
                state = .empty
                return
            }
            queue = cards
            totalCount = cards.count
            doneCount = 0
            current = queue.first
            state = .reviewing
        }
    }

    func reveal() {
        isRevealed = true
    }

    func rate(_ rating: ReviewRating) {
        guard state == .reviewing, let card = current else { return }
        let now = Date()
        let outcome = ReviewScheduler.review(card: card, rating: rating, now: now)
        Task { @MainActor in
            try? await DatabaseManager.shared.applyReview(
                card: card, rating: rating, outcome: outcome, at: now
            )
            advance(after: card, rating: rating, outcome: outcome)
        }
    }

    private func advance(after card: SRSCard, rating: ReviewRating, outcome: ReviewScheduler.Outcome) {
        if !queue.isEmpty {
            queue.removeFirst()
        }
        if rating == .again {
            // 「ダメ」は同セッションの最後にもう一度出す（更新後の状態で）
            var retry = card
            retry.stability = outcome.stability
            retry.difficulty = outcome.difficulty
            retry.reviewCount += 1
            queue.append(retry)
        } else {
            doneCount += 1
        }
        isRevealed = false
        current = queue.first
        if queue.isEmpty {
            state = .finished
        }
    }
}

struct ReviewView: View {
    @StateObject var model: ReviewModel

    var body: some View {
        Group {
            switch model.state {
            case .loading:
                ProgressView()
            case .empty:
                ContentUnavailableView(
                    "復習するカードはありません",
                    systemImage: "checkmark.rectangle.stack",
                    description: Text("週次レポートでカード候補を承認すると、ここで復習できます。")
                )
            case .limitReached:
                ContentUnavailableView(
                    "今日の復習は上限に達しました",
                    systemImage: "moon.zzz",
                    description: Text("1日\(ReviewModel.dailyLimit)枚まで。また明日どうぞ。")
                )
            case .finished:
                ContentUnavailableView(
                    "今日の復習はここまで！",
                    systemImage: "party.popper",
                    description: Text("\(model.doneCount)枚を復習しました。")
                )
            case .reviewing:
                reviewBody
            }
        }
        .frame(width: 480, height: 420)
        .onAppear { model.startSession() }
    }

    private var reviewBody: some View {
        VStack(spacing: 12) {
            HStack {
                Text("\(model.doneCount) / \(model.totalCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
            }

            Spacer()

            // 表: 日本語（言いたいこと・意味）
            Text(model.current?.front ?? "")
                .font(.title3)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)

            if model.isRevealed, let card = model.current {
                Divider()
                    .padding(.horizontal, 40)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(card.back)
                        .font(.title2.weight(.medium))
                        .multilineTextAlignment(.center)
                        .textSelection(.enabled)
                    Button {
                        SpeechSpeaker.shared.speak(card.back, languageCode: "en")
                    } label: {
                        Image(systemName: "speaker.wave.2.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("読み上げ")
                }
            }

            Spacer()

            if model.isRevealed {
                HStack(spacing: 12) {
                    Button("ダメ") { model.rate(.again) }
                        .keyboardShortcut("1", modifiers: [])
                        .tint(.red)
                    Button("まあまあ") { model.rate(.good) }
                        .keyboardShortcut("2", modifiers: [])
                    Button("余裕") { model.rate(.easy) }
                        .keyboardShortcut("3", modifiers: [])
                        .tint(.green)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                Text("キー: 1 = ダメ / 2 = まあまあ / 3 = 余裕")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                Button("答えを見る") { model.reveal() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.space, modifiers: [])
                Text("スペースキーでも表示できます")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(20)
    }
}
