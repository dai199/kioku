import Foundation

/// 翻訳結果のインメモリキャッシュ（LRU）。
/// 同じテキストを選択し直したときにAPIを呼ばず即表示する。
///
/// キーにエンジンの版（`TranslationEngine.promptVersion`）を含めるので、
/// プロンプト変更後もエンジン切り替え後も自然に無効化される。
/// 含めないと、Apple Translationに切り替えたのにGeminiの訳が返る、といった事故になる。
@MainActor
final class TranslationCache {
    private let capacity = 300
    private var storage: [String: String] = [:]
    private var order: [String] = []

    func lookup(text: String, source: String, target: String, version: String) -> String? {
        let key = Self.key(text, source, target, version)
        guard let value = storage[key] else { return nil }
        order.removeAll { $0 == key }
        order.append(key)
        return value
    }

    func store(
        _ translation: String, text: String, source: String, target: String, version: String
    ) {
        let key = Self.key(text, source, target, version)
        if storage[key] == nil {
            order.append(key)
        }
        storage[key] = translation
        while order.count > capacity {
            storage.removeValue(forKey: order.removeFirst())
        }
    }

    private static func key(
        _ text: String, _ source: String, _ target: String, _ version: String
    ) -> String {
        "\(source)>\(target)|\(version)|\(text)"
    }
}
