import Foundation

/// chrF（文字n-gramのF値）。訳文が参照訳にどれだけ近いかを0〜1で返す。
///
/// BLEUではなくchrFを選んだのは、**日本語に分かち書きが要らない**から。
/// 語単位の指標は日本語で形態素解析器に依存し、その選択で数字が動いてしまう。
///
/// 参照訳には「ユーザーが採用した訳」を使う（SPEC §12のゴールデンセット）。
/// 単独では粗い指標だが、**同じ原文セットでエンジン同士を比べる**用途では十分機能する。
enum ChrF {
    /// βは再現率を精度の何倍重く見るか。原典（Popović 2015）に倣って2。
    /// 訳の抜けを重く見るという意味で、翻訳の評価には妥当
    static let beta = 2.0
    static let maxN = 6

    static func score(hypothesis: String, reference: String, maxN: Int = maxN) -> Double {
        // 空白は文字種として数えない。日本語と英語で空白の量が違いすぎ、
        // 入れると言語ごとに下駄が変わる
        let hyp = Array(hypothesis.filter { !$0.isWhitespace })
        let ref = Array(reference.filter { !$0.isWhitespace })
        guard !hyp.isEmpty, !ref.isEmpty else { return 0 }

        var precisions: [Double] = []
        var recalls: [Double] = []

        for n in 1...maxN {
            guard hyp.count >= n, ref.count >= n else { continue }
            let hypGrams = counts(of: hyp, n: n)
            let refGrams = counts(of: ref, n: n)

            // 一致数は「両者に共通して現れた回数」。多く出しただけで得しないよう min を取る
            var matched = 0
            for (gram, count) in hypGrams {
                matched += min(count, refGrams[gram] ?? 0)
            }
            let hypTotal = hypGrams.values.reduce(0, +)
            let refTotal = refGrams.values.reduce(0, +)
            precisions.append(hypTotal == 0 ? 0 : Double(matched) / Double(hypTotal))
            recalls.append(refTotal == 0 ? 0 : Double(matched) / Double(refTotal))
        }
        guard !precisions.isEmpty else { return 0 }

        let precision = precisions.reduce(0, +) / Double(precisions.count)
        let recall = recalls.reduce(0, +) / Double(recalls.count)
        guard precision + recall > 0 else { return 0 }

        let b2 = beta * beta
        return (1 + b2) * precision * recall / (b2 * precision + recall)
    }

    private static func counts(of chars: [Character], n: Int) -> [String: Int] {
        var result: [String: Int] = [:]
        guard chars.count >= n else { return result }
        for i in 0...(chars.count - n) {
            result[String(chars[i..<(i + n)]), default: 0] += 1
        }
        return result
    }
}
