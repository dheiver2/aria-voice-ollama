import AVFoundation
import Foundation

@MainActor
class SpeechOutput: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published var isSpeaking = false

    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - Seleção de voz

    private func bestVoice() -> AVSpeechSynthesisVoice? {
        let all = AVSpeechSynthesisVoice.speechVoices()
        let ptBR = all.filter { $0.language == "pt-BR" }

        // Prioridade: Premium > Enhanced > Eloquence feminina > qualquer pt-BR
        let priority = [
            "com.apple.voice.premium.pt-BR.Luciana",
            "com.apple.voice.enhanced.pt-BR.Luciana",
            "com.apple.eloquence.pt-BR.Sandy",
            "com.apple.eloquence.pt-BR.Shelley",
            "com.apple.eloquence.pt-BR.Flo",
            "com.apple.voice.compact.pt-BR.Luciana",
        ]

        for id in priority {
            if let v = AVSpeechSynthesisVoice(identifier: id) { return v }
        }

        // Fallback: primeiro Eloquence feminino disponível
        let femNames = ["Sandy", "Shelley", "Flo", "Luciana"]
        for name in femNames {
            if let v = ptBR.first(where: { $0.name.contains(name) }) { return v }
        }

        return ptBR.first ?? AVSpeechSynthesisVoice(language: "pt-BR")
    }

    // MARK: - Falar

    func speak(_ text: String) {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        // Pré-processar texto para soar mais natural
        let processed = preprocess(text)

        let utterance = AVSpeechUtterance(string: processed)
        utterance.voice          = bestVoice()
        utterance.rate           = 0.50   // natural — não modifica pitch artificialmente
        utterance.pitchMultiplier = 1.0   // neutro — Eloquence já tem timbre feminino
        utterance.volume         = 1.0
        utterance.preUtteranceDelay  = 0.05
        utterance.postUtteranceDelay = 0.05
        synthesizer.speak(utterance)
        isSpeaking = true
    }

    func stopSpeaking() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }

    // MARK: - Pré-processamento de texto

    /// Torna o texto mais natural para TTS:
    /// expande abreviações, remove emojis, ajusta pontuação
    private func preprocess(_ text: String) -> String {
        var t = text

        // Remove emojis e símbolos TTS não fala bem
        let emojiPattern = try? NSRegularExpression(
            pattern: #"[\x{1F000}-\x{1FFFF}\x{2600}-\x{27FF}\x{FE00}-\x{FEFF}]+"#,
            options: []
        )
        if let rx = emojiPattern {
            t = rx.stringByReplacingMatches(in: t, range: NSRange(t.startIndex..., in: t), withTemplate: "")
        }

        // Expande siglas comuns
        let expansions: [(String, String)] = [
            ("✅", ""), ("⚠️", ""), ("❌", ""), ("🧪", ""), ("💬", ""),
            ("CPU:", "CPU:"), ("RAM:", "memória:"),
            ("KB", "kilobytes"), ("MB", "megabytes"), ("GB", "gigabytes"),
            ("https://", ""), ("http://", ""),
            ("~/Desktop", "área de trabalho"),
            ("~/Downloads", "downloads"),
        ]
        for (from, to) in expansions {
            t = t.replacingOccurrences(of: from, with: to)
        }

        // Remove caracteres de controle e espaços extras
        t = t.replacingOccurrences(of: "  ", with: " ")
        t = t.trimmingCharacters(in: .whitespacesAndNewlines)

        // Trunca respostas muito longas (TTS fica chato acima de ~200 chars)
        if t.count > 220 {
            let idx = t.index(t.startIndex, offsetBy: 200)
            if let dotIdx = t[..<idx].lastIndex(of: ".") {
                t = String(t[...dotIdx])
            } else if let spaceIdx = t[..<idx].lastIndex(of: " ") {
                t = String(t[..<spaceIdx]) + "."
            } else {
                t = String(t[..<idx]) + "."
            }
        }

        return t
    }

    // MARK: - Delegate

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }
}
