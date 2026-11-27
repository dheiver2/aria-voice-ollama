import Foundation

/// Idioma do app (reconhecimento de fala, voz e respostas do LLM). Padrão: inglês.
/// Para português do Brasil: `defaults write com.dheiver.aria-voice language pt`
/// (ou variável de ambiente ARIA_LANG=pt).
enum AppLanguage {
    static var code: String {
        let raw = ProcessInfo.processInfo.environment["ARIA_LANG"]
            ?? UserDefaults.standard.string(forKey: "language")
            ?? "en"
        return raw.lowercased().hasPrefix("pt") ? "pt" : "en"
    }

    static var isPT: Bool { code == "pt" }

    /// Identificador de locale para SFSpeechRecognizer e AVSpeechSynthesisVoice.
    static var localeID: String { isPT ? "pt-BR" : "en-US" }

    /// Nome do idioma em inglês, usado no prompt do LLM.
    static var name: String { isPT ? "Brazilian Portuguese" : "English" }
}
