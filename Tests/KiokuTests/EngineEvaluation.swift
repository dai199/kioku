import Foundation
import GRDB
import Testing
@testable import Kioku

/// 翻訳エンジンの比較。**通常のテストではなく、手で回す計測**。
/// `make eval` からのみ動く（実DBと実APIを使い、時間も費用もかかるため）。
///
/// テストターゲットに置いたのは、プロンプト・エンジン・chrFをそのまま使えるから。
/// 別のツールに切り出すとプロンプトを二重に持つことになり、
/// 「何を比べているのか」が保証できなくなる。
@Suite("エンジン比較（make eval）")
struct EngineEvaluation {
    /// 実DBの原文を使うため、結果には利用者の実際の文が入る。
    /// 出力先は .gitignore 済み（公開リポジトリに実データを載せない）
    private static let outputDirectory = "eval-results"

    /// テストプロセスの作業ディレクトリは `/` なので、
    /// ソースの位置からリポジトリの場所を求める
    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Tests/KiokuTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // リポジトリの根
    }

    /// 件数は make が書いたファイルから読む（環境変数が届かないため）
    private static var requestedLimit: Int {
        let path = repositoryRoot.appendingPathComponent(".eval-limit")
        return (try? String(contentsOf: path, encoding: .utf8))
            .flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) } ?? 20
    }

    /// 通常の `make test` からは `-skip-testing` で除外している。
    /// 環境変数で切り替えないのは、xcodebuildがテストプロセスへ変数を渡さないため
    /// （TEST_RUNNER_接頭辞でも届かず、黙ってスキップされた）。
    @Test("3エンジンを同じ原文で比較する")
    func compareEngines() async throws {
        let limit = Self.requestedLimit
        let settings = await AppSettings()
        let samples = try await loadSamples(limit: limit)
        try #require(!samples.isEmpty, "翻訳ログが空です。まず何度か翻訳してください。")

        var engines: [(name: String, engine: TranslationEngine)] = []
        let apiKey = await settings.geminiAPIKey
        if !apiKey.isEmpty {
            let model = await settings.translationModel
            engines.append(("Gemini", GeminiEngine(apiKey: apiKey, model: model)))
        }
        if #available(macOS 26.4, *) {
            engines.append(("Apple翻訳", AppleTranslationEngine()))
        }
        if #available(macOS 26.0, *), FoundationModelsEngine.availabilityMessage == nil {
            engines.append(("Apple Intelligence", FoundationModelsEngine()))
        }
        try #require(engines.count >= 2, "比較には2つ以上のエンジンが要ります。")

        var report = header(samples: samples, engines: engines.map(\.name))
        var summaries: [String] = []

        for (name, engine) in engines {
            var results: [Result] = []
            for sample in samples {
                results.append(await evaluate(sample: sample, engine: engine))
            }
            let scored = await judge(results: results, apiKey: apiKey, settings: settings)
            summaries.append(summaryRow(name: name, results: scored))
            report += detail(name: name, results: scored)
        }

        report = report.replacingOccurrences(
            of: "{{SUMMARY}}", with: summaries.joined(separator: "\n")
        )
        let path = try write(report)
        print("\n評価結果を書き出しました: \(path)\n")
        print(report)
    }

    // MARK: - 評価の1件

    private struct Sample {
        let sourceText: String
        let sourceLang: String
        let targetLang: String
        /// ユーザーが採用した訳。あればchrFの参照に使う
        let reference: String?
    }

    private struct Result {
        let sample: Sample
        let output: String
        let seconds: Double
        let failure: String?
        var judgeScore: Double?

        var lengthRatio: Double {
            guard !sample.sourceText.isEmpty else { return 0 }
            return Double(output.count) / Double(sample.sourceText.count)
        }
        var chrf: Double? {
            guard let reference = sample.reference, !output.isEmpty else { return nil }
            return ChrF.score(hypothesis: output, reference: reference)
        }
    }

    private func evaluate(sample: Sample, engine: TranslationEngine) async -> Result {
        let started = Date()
        do {
            let output = try await engine.translate(TranslationRequest(
                text: sample.sourceText,
                sourceLanguage: sample.sourceLang,
                targetLanguage: sample.targetLang
            ))
            return Result(sample: sample, output: output,
                          seconds: Date().timeIntervalSince(started), failure: nil)
        } catch {
            return Result(sample: sample, output: "",
                          seconds: Date().timeIntervalSince(started),
                          failure: error.localizedDescription)
        }
    }

    // MARK: - 原文の取り出し

    /// 方向ごとに均等に取り、長さ順に散らす。
    /// 同じ文が何度も翻訳されていることがあるので重複は除く。
    private func loadSamples(limit: Int) async throws -> [Sample] {
        let store = DatabaseManager.shared
        // 採用された訳を原文で引けるようにしておく（chrFの参照）
        let references: [String: String] = try await store.dbQueue.read { db in
            var map: [String: String] = [:]
            let rows = try Row.fetchAll(db, sql: """
                SELECT sourceText, candidatesJSON, adoptedIndex FROM translationSession
                WHERE adoptedIndex IS NOT NULL
                """)
            for row in rows {
                guard let source: String = row["sourceText"],
                      let json: String = row["candidatesJSON"],
                      let index: Int = row["adoptedIndex"],
                      let candidates = try? JSONDecoder().decode(
                          [String].self, from: Data(json.utf8)
                      ),
                      candidates.indices.contains(index)
                else { continue }
                map[source] = candidates[index]
            }
            return map
        }

        let logs = try await store.dbQueue.read { db in
            try TranslationLog.order(Column("createdAt").desc).fetchAll(db)
        }
        var seen = Set<String>()
        var byDirection: [String: [Sample]] = [:]
        for log in logs {
            guard seen.insert(log.sourceText).inserted else { continue }
            byDirection[log.sourceLang, default: []].append(Sample(
                sourceText: log.sourceText,
                sourceLang: log.sourceLang,
                targetLang: log.targetLang,
                reference: references[log.sourceText]
            ))
        }
        // 方向ごとに交互に拾い、片方に偏らないようにする
        var samples: [Sample] = []
        let perDirection = max(1, limit / max(1, byDirection.count))
        for (_, list) in byDirection.sorted(by: { $0.key < $1.key }) {
            samples += list.prefix(perDirection)
        }
        return Array(samples.prefix(limit))
    }

    // MARK: - LLM採点（参照訳が無くても効く）

    private func judge(
        results: [Result], apiKey: String, settings: AppSettings
    ) async -> [Result] {
        guard !apiKey.isEmpty else { return results }
        let model = await settings.analysisModel
        let client = GeminiClient(apiKey: apiKey, model: model)
        var scored = results
        for (index, result) in results.enumerated() where result.failure == nil {
            let prompt = """
            You are evaluating a machine translation. Score it on three criteria, 1 to 5.

            accuracy: does it preserve the meaning of the source, without omission or addition?
            fluency: does it read as if written by a native speaker, not translated?
            register: does it match the tone and formality of the source?

            Reply with JSON only: {"accuracy": n, "fluency": n, "register": n}

            Source: \(result.sample.sourceText)
            Translation: \(result.output)
            """
            guard let raw = try? await client.generateText(
                prompt: prompt, temperature: 0, jsonResponse: true
            ),
                let scores = try? JSONDecoder().decode(
                    [String: Double].self, from: WeeklyAnalyzer.extractJSONData(raw)
                ),
                !scores.isEmpty
            else { continue }
            scored[index].judgeScore = scores.values.reduce(0, +) / Double(scores.count)
        }
        return scored
    }

    // MARK: - 出力

    private func header(samples: [Sample], engines: [String]) -> String {
        let withReference = samples.filter { $0.reference != nil }.count
        return """
        # エンジン比較

        - 原文: \(samples.count)件（うち参照訳あり \(withReference)件）
        - エンジン: \(engines.joined(separator: " / "))

        ## まとめ

        | エンジン | 平均スコア | 長さ比 | chrF | 所要(中央値) | 失敗 |
        |---|---|---|---|---|---|
        {{SUMMARY}}

        スコアは意味の忠実性・自然さ・レジスター一致の平均（1〜5）。
        長さ比は訳文÷原文の文字数。同方向で比べたとき、大きいほど冗長。
        chrFは採用済みの訳との一致度（0〜1）。参照訳がある文のみ。

        """
    }

    private func summaryRow(name: String, results: [Result]) -> String {
        let ok = results.filter { $0.failure == nil }
        let scores = ok.compactMap(\.judgeScore)
        let chrfs = ok.compactMap(\.chrf)
        let times = ok.map(\.seconds).sorted()
        func avg(_ xs: [Double]) -> String {
            xs.isEmpty ? "—" : String(format: "%.2f", xs.reduce(0, +) / Double(xs.count))
        }
        let median = times.isEmpty ? "—" : String(format: "%.2f秒", times[times.count / 2])
        return "| \(name) | \(avg(scores)) | \(avg(ok.map(\.lengthRatio))) "
            + "| \(avg(chrfs)) | \(median) | \(results.count - ok.count) |"
    }

    private func detail(name: String, results: [Result]) -> String {
        var text = "\n## \(name)\n\n"
        for result in results {
            text += "- `\(result.sample.sourceLang)→\(result.sample.targetLang)` "
            text += "\(result.sample.sourceText)\n"
            if let failure = result.failure {
                text += "  - **失敗**: \(failure)\n"
                continue
            }
            text += "  - \(result.output)\n"
            var facts = [String(format: "長さ比 %.2f", result.lengthRatio),
                         String(format: "%.2f秒", result.seconds)]
            if let score = result.judgeScore { facts.append(String(format: "採点 %.1f", score)) }
            if let chrf = result.chrf { facts.append(String(format: "chrF %.2f", chrf)) }
            text += "  - \(facts.joined(separator: " / "))\n"
        }
        return text
    }

    private func write(_ report: String) throws -> String {
        let directory = Self.repositoryRoot
            .appendingPathComponent(Self.outputDirectory, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let file = directory.appendingPathComponent("\(stamp).md")
        try report.write(to: file, atomically: true, encoding: .utf8)
        return file.path
    }
}
