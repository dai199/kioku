import Foundation

/// 翻訳結果のインメモリキャッシュ（LRU）。
/// 同じテキストを選択し直したときにAPIを呼ばず即表示する。
/// プロンプトバージョンをキーに含めるので、プロンプト変更後は自然に無効化される。
@MainActor
final class TranslationCache {
    private let capacity = 300
    private var storage: [String: String] = [:]
    private var order: [String] = []

    func lookup(text: String, source: String, target: String) -> String? {
        let key = Self.key(text, source, target)
        guard let value = storage[key] else { return nil }
        order.removeAll { $0 == key }
        order.append(key)
        return value
    }

    func store(_ translation: String, text: String, source: String, target: String) {
        let key = Self.key(text, source, target)
        if storage[key] == nil {
            order.append(key)
        }
        storage[key] = translation
        while order.count > capacity {
            storage.removeValue(forKey: order.removeFirst())
        }
    }

    private static func key(_ text: String, _ source: String, _ target: String) -> String {
        "\(source)>\(target)|\(GeminiEngine.promptVersion)|\(text)"
    }
}
