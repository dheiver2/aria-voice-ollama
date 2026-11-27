import SwiftUI
import Combine

@MainActor
class FloatingViewModel: ObservableObject {
    @Published var orbState: OrbState  = .idle
    @Published var transcription       = ""
    @Published var responseText        = ""
    @Published var audioLevel: Float   = 0
    @Published var modelName           = ""
    @Published var hint                = "Tap the orb to speak"
    @Published var historyVisible      = false

    private let voice   = VoiceManager()
    private let ollama  = OllamaService()
    private let tts     = SpeechOutput()
    private let router  = AgentRouter()

    private var history: [ChatMessage] = []
    var onClose: (() -> Void)?
    var onShowHistory: (() -> Void)?
    var onShowSettings: (() -> Void)?

    // Auto-close timer after response
    private var closeTimer: Timer?

    init() {
        setupVoice()
        Task { await loadModel() }
    }

    private func loadModel() async {
        await ollama.checkConnection()
        modelName = ollama.selectedModel
    }

    // MARK: - Orb tap
    func handleOrbTap() {
        switch orbState {
        case .idle:
            startListening()
        case .listening:
            voice.stopListening()
        case .speaking:
            tts.stopSpeaking()
            orbState = .idle
            scheduleClose()
        case .processing:
            break
        }
    }

    func startListening() {
        closeTimer?.invalidate()
        responseText   = ""
        transcription  = ""
        orbState       = .listening
        voice.startListening()
    }

    // MARK: - Voice setup
    private func setupVoice() {
        voice.onTranscriptionComplete = { [weak self] text in
            Task { @MainActor [weak self] in
                self?.transcription = text
                await self?.sendToAI(text)
            }
        }
    }

    // MARK: - AI call with streaming
    private func sendToAI(_ text: String) async {
        guard ollama.isConnected else {
            responseText = "Ollama offline. Start it with: ollama serve"
            orbState = .idle
            return
        }

        history.append(ChatMessage(role: "user", content: text))
        orbState     = .processing
        responseText = ""

        do {
            // Stream response token-by-token
            var fullRaw = ""
            for try await chunk in ollama.streamChat(history: history) {
                fullRaw += chunk
                // Show streaming text (extract fala field if partial JSON)
                let preview = extractFala(from: fullRaw) ?? fullRaw
                responseText = preview
                if orbState != .speaking { orbState = .processing }
            }

            // Full response received — execute action
            let spoken = await router.process(fullRaw)
            history.append(ChatMessage(role: "assistant", content: spoken))

            // Speak response
            orbState = .speaking
            responseText = spoken
            tts.speak(spoken)

            // Wait for TTS to finish then close
            waitForTTSThenClose()

        } catch {
            responseText = "Failed to connect to Ollama."
            orbState = .idle
            scheduleClose(after: 4)
        }
    }

    private func waitForTTSThenClose() {
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            Task { @MainActor [weak self] in
                guard let self else { timer.invalidate(); return }
                if !self.tts.isSpeaking {
                    timer.invalidate()
                    self.orbState = .idle
                    self.scheduleClose(after: 2.5)
                }
            }
        }
    }

    private func scheduleClose(after delay: Double = 3) {
        closeTimer?.invalidate()
        closeTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.close()
            }
        }
    }

    // MARK: - Helpers
    private func extractFala(from raw: String) -> String? {
        let clean = raw.replacingOccurrences(of: "```json", with: "")
                       .replacingOccurrences(of: "```", with: "")
        guard let start = clean.firstIndex(of: "{"),
              let end   = clean.lastIndex(of: "}") else { return nil }
        let jsonStr = String(clean[start...end])
        guard let data = jsonStr.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json["fala"] as? String
    }

    func close() {
        closeTimer?.invalidate()
        tts.stopSpeaking()
        voice.stopListening()
        transcription = ""
        responseText  = ""
        orbState      = .idle
        onClose?()
    }

    func showHistory()  { onShowHistory?() }
    func showSettings() { onShowSettings?() }
}
