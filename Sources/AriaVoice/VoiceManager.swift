import AVFoundation
import Speech
import Combine

@MainActor
class VoiceManager: NSObject, ObservableObject {
    @Published var isListening = false
    @Published var transcribedText = ""
    @Published var audioLevel: Float = 0
    @Published var isAvailable = false
    @Published var permissionStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined
    @Published var micPermission: AVAuthorizationStatus = .notDetermined

    var onTranscriptionComplete: ((String) -> Void)?

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: AppLanguage.localeID))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var silenceTimer: Timer?
    private var lastTranscription = ""

    override init() {
        super.init()
        checkAndRequestPermissions()
    }

    // MARK: - Permissões

    func checkAndRequestPermissions() {
        // 1. Verifica microfone
        micPermission = AVCaptureDevice.authorizationStatus(for: .audio)
        if micPermission == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                Task { @MainActor [weak self] in
                    self?.micPermission = granted ? .authorized : .denied
                    if granted { self?.requestSpeechPermission() }
                    else { self?.updateAvailability() }
                }
            }
        } else {
            requestSpeechPermission()
        }
    }

    private func requestSpeechPermission() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor [weak self] in
                self?.permissionStatus = status
                self?.updateAvailability()
            }
        }
    }

    private func updateAvailability() {
        let micOK     = micPermission == .authorized
        let speechOK  = permissionStatus == .authorized
        let recogOK   = speechRecognizer?.isAvailable ?? false
        isAvailable   = micOK && speechOK && recogOK
        if micOK && speechOK && !recogOK {
            transcribedText = "⚠️ Speech recognition (\(AppLanguage.localeID)) is unavailable on this Mac. Check the dictation languages in System Settings."
        }
        print("[VoiceManager] mic=\(micOK) speech=\(speechOK) recognizer=\(recogOK) → available=\(isAvailable)")
    }

    // MARK: - Toggle

    func toggleListening() {
        if isListening {
            stopListening()
        } else {
            startListening()
        }
    }

    func startListening() {
        guard !isListening else { return }

        // Re-verifica permissões em tempo real (mic e fala — captura grants feitos
        // em Ajustes do Sistema após o launch, que de outro modo só seriam vistos ao reabrir o app)
        micPermission = AVCaptureDevice.authorizationStatus(for: .audio)
        permissionStatus = SFSpeechRecognizer.authorizationStatus()
        updateAvailability()

        if micPermission == .denied || micPermission == .restricted {
            transcribedText = "⚠️ Microphone access denied. Go to System Settings > Privacy > Microphone and allow ÁRIA."
            return
        }
        if permissionStatus == .denied || permissionStatus == .restricted {
            transcribedText = "⚠️ Speech recognition denied. Go to System Settings > Privacy > Speech Recognition and allow ÁRIA."
            return
        }
        if micPermission == .notDetermined || permissionStatus == .notDetermined {
            transcribedText = "⏳ Requesting permissions... Approve the system dialogs."
            checkAndRequestPermissions()
            return
        }
        guard isAvailable else {
            transcribedText = "⚠️ Microphone/speech permissions unavailable. Check System Settings > Privacy."
            return
        }

        transcribedText = ""
        lastTranscription = ""

        // Remove tap anterior se houver (evita crash em restart)
        audioEngine.inputNode.removeTap(onBus: 0)

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else { return }
        request.shouldReportPartialResults = true
        request.taskHint = .dictation

        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }

                if let result = result {
                    let text = result.bestTranscription.formattedString
                    self.transcribedText = text
                    self.lastTranscription = text
                    self.resetSilenceTimer()
                }

                if let error = error {
                    let code = (error as NSError).code
                    // Código 1110 = gravação parou (normal ao stopListening)
                    // Código 203  = job cancelado
                    if code != 1110 && code != 203 {
                        print("[VoiceManager] Erro STT \(code): \(error.localizedDescription)")
                        self.transcribedText = "⚠️ Speech error (\(code)): \(error.localizedDescription)"
                        self.lastTranscription = ""   // não despachar transcrição inválida em erro real
                    }
                    self.stopListening()
                    return
                }

                if result?.isFinal == true {
                    self.stopListening()
                }
            }
        }

        let inputNode = audioEngine.inputNode
        var format = inputNode.outputFormat(forBus: 0)
        if format.sampleRate <= 0 || format.channelCount == 0 {
            // outputFormat pode vir inválido (0 Hz / 0 canais) antes do engine configurar;
            // inputFormat reflete o formato real do hardware do microfone.
            format = inputNode.inputFormat(forBus: 0)
        }
        guard format.sampleRate > 0, format.channelCount > 0 else {
            isListening = false
            transcribedText = "⚠️ Microphone unavailable (invalid audio format). Check the input device."
            recognitionTask?.cancel()
            recognitionTask = nil
            recognitionRequest = nil
            return
        }
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
            self?.updateAudioLevel(buffer: buffer)
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
            isListening = true
            print("[VoiceManager] Recording started")
        } catch {
            isListening = false
            transcribedText = "⚠️ Failed to start audio: \(error.localizedDescription)"
            print("[VoiceManager] Erro ao iniciar audioEngine: \(error)")
        }
    }

    func stopListening() {
        guard isListening else { return }
        silenceTimer?.invalidate()
        silenceTimer = nil
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        isListening = false

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.audioLevel = 0
        }

        let text = lastTranscription.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            print("[VoiceManager] Transcrito: \(text)")
            onTranscriptionComplete?(text)
            transcribedText = ""
        } else if !transcribedText.hasPrefix("⚠️") {
            transcribedText = "I didn't catch that. Tap the microphone and speak again."
        }
    }

    // MARK: - Helpers

    private func updateAudioLevel(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<frameLength { sum += channelData[i] * channelData[i] }
        let rms = sqrt(sum / Float(max(frameLength, 1)))
        let level = min(rms * 20, 1.0)
        Task { @MainActor [weak self] in self?.audioLevel = level }
    }

    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 1.8, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in self?.stopListening() }
        }
    }
}
