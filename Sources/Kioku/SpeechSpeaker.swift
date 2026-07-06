import AVFoundation

/// 原文・訳文の読み上げ（macOS内蔵TTS・無料/オフライン）。
@MainActor
final class SpeechSpeaker {
    static let shared = SpeechSpeaker()

    private let synthesizer = AVSpeechSynthesizer()

    func speak(_ text: String, languageCode: String) {
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(
            language: languageCode == "ja" ? "ja-JP" : "en-US"
        )
        synthesizer.speak(utterance)
    }
}
