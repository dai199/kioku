import Foundation

enum ReviewRating: String, Sendable {
    case again  // ダメ
    case good   // まあまあ
    case easy   // 余裕
}

/// 間隔反復のスケジューラ（SM-2系の簡易実装）。
/// SRSCardのカラムは stability=間隔（日）、difficulty=易しさ係数 として使う。
/// 本格的なFSRSへの差し替えはこの型の置き換えだけで済むようにしてある。
enum ReviewScheduler {
    struct Outcome: Sendable {
        let stability: Double   // 次回までの間隔（日）
        let difficulty: Double  // 易しさ係数
        let dueDate: Date
        let isLapse: Bool
    }

    static func review(card: SRSCard, rating: ReviewRating, now: Date = Date()) -> Outcome {
        let interval = card.stability
        let ease = card.difficulty > 0 ? card.difficulty : 2.5

        switch rating {
        case .again:
            // 同じ日にもう一度。易しさ係数を下げる
            return Outcome(
                stability: 0,
                difficulty: max(1.3, ease - 0.2),
                dueDate: now.addingTimeInterval(10 * 60),
                isLapse: card.reviewCount > 0
            )
        case .good:
            let next = interval <= 0 ? 1 : min(interval * ease, 365)
            return Outcome(
                stability: next,
                difficulty: ease,
                dueDate: now.addingTimeInterval(next * 24 * 3600),
                isLapse: false
            )
        case .easy:
            let newEase = min(3.0, ease + 0.15)
            let next = interval <= 0 ? 4 : min(interval * newEase * 1.3, 365)
            return Outcome(
                stability: next,
                difficulty: newEase,
                dueDate: now.addingTimeInterval(next * 24 * 3600),
                isLapse: false
            )
        }
    }
}
