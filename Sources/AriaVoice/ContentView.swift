import SwiftUI
import AppKit

struct ContentView: View {
    @StateObject private var voice   = VoiceManager()
    @StateObject private var ollama  = OllamaService()
    @StateObject private var tts     = SpeechOutput()
    @StateObject private var router  = AgentRouter()

    @State private var messages: [ChatMessage] = []
    @State private var isProcessing = false
    @State private var statusText   = "Tap the microphone to speak"
    @State private var showSettings = false
    @State private var showDebug    = false
    @State private var pulseScale: CGFloat = 1.0
    @State private var glowOpacity: Double = 0.4

    private let bg1     = Color(hex: "080810")
    private let bg2     = Color(hex: "0D0820")
    private let accent  = Color(hex: "7C3AED")
    private let accentL = Color(hex: "A78BFA")
    private let micRed  = Color(hex: "EF4444")

    var body: some View {
        ZStack {
            backgroundGradient
            VStack(spacing: 0) {
                headerBar
                Divider().opacity(0.1)
                if showDebug {
                    debugPanel
                    Divider().opacity(0.1)
                }
                chatHistory
                Divider().opacity(0.1)
                bottomPanel
            }
        }
        .frame(minWidth: 520, idealWidth: 560, maxWidth: 700,
               minHeight: 700, idealHeight: 760)
        .onAppear {
            // Re-tenta até conectar: evita ficar "Offline" travado quando o app
            // sobe antes do Ollama/modelo estar pronto (corrida de launch).
            Task {
                for _ in 0..<10 {
                    await ollama.checkConnection()
                    if ollama.isConnected { break }
                    try? await Task.sleep(nanoseconds: 3_000_000_000) // 3s
                }
            }
            setupVoice()
            startAnimations()
        }
    }

    // MARK: - Background
    var backgroundGradient: some View {
        ZStack {
            LinearGradient(colors: [bg1, bg2], startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [accent.opacity(0.08), .clear], center: .bottom,
                           startRadius: 10, endRadius: 400)
        }.ignoresSafeArea()
    }

    // MARK: - Header
    var headerBar: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(accent.opacity(0.2)).frame(width: 40, height: 40)
                Text("Ā").font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(LinearGradient(colors: [accentL, accent],
                                                   startPoint: .top, endPoint: .bottom))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("ÁRIA").font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(LinearGradient(colors: [.white, accentL],
                                                   startPoint: .leading, endPoint: .trailing))
                Text("Assistente de Voz • MacBook Pro")
                    .font(.system(size: 10)).foregroundColor(.white.opacity(0.4))
            }
            Spacer()

            // Ação atual
            if !router.lastAction.isEmpty && router.lastAction != "nenhuma" {
                HStack(spacing: 5) {
                    Image(systemName: actionIcon(router.lastAction))
                        .font(.system(size: 10))
                        .foregroundColor(accentL)
                    Text(router.lastAction)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(accent.opacity(0.15))
                .clipShape(Capsule())
                .transition(.scale.combined(with: .opacity))
            }

            connectionBadge

            // Debug toggle
            Button(action: { showDebug.toggle() }) {
                Image(systemName: showDebug ? "ant.fill" : "ant")
                    .font(.system(size: 13))
                    .foregroundColor(showDebug ? accentL : .white.opacity(0.3))
            }.buttonStyle(.plain).help("Debug")

            Button(action: { showSettings.toggle() }) {
                Image(systemName: "gearshape.fill").font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.3))
            }.buttonStyle(.plain)
            .popover(isPresented: $showSettings) { settingsPanel }
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    var connectionBadge: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(ollama.isConnected ? Color(hex: "22C55E") : Color(hex: "EF4444"))
                .frame(width: 6, height: 6)
                .shadow(color: ollama.isConnected ? .green : .red, radius: 3)
            Text(ollama.isConnected ? "Online" : "Offline")
                .font(.system(size: 10)).foregroundColor(.white.opacity(0.5))
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(.white.opacity(0.06)).clipShape(Capsule())
    }

    // MARK: - Debug Panel
    var debugPanel: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Debug — Agentes")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(accentL)
                Spacer()
                Button("Clear") { router.debugLog.removeAll() }
                    .font(.system(size: 9)).foregroundColor(.white.opacity(0.3))
                    .buttonStyle(.plain)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(router.debugLog.suffix(12), id: \.self) { line in
                        Text(line)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(line.hasPrefix("✅") ? Color(hex: "22C55E") :
                                             line.hasPrefix("⚠️") || line.hasPrefix("⛔") ? Color(hex: "FBBF24") :
                                             line.hasPrefix("🎯") ? accentL : .white.opacity(0.5))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxHeight: 90)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(.black.opacity(0.3))
    }

    // MARK: - Chat History
    var chatHistory: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if messages.isEmpty { emptyState }
                    else {
                        ForEach(messages) { msg in
                            MessageBubble(message: msg).id(msg.id)
                        }
                    }
                    if isProcessing { processingIndicator.id("proc") }
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
            }
            .onChange(of: messages.count) { _ in
                withAnimation { proxy.scrollTo(messages.last?.id, anchor: .bottom) }
            }
            .onChange(of: isProcessing) { _ in
                withAnimation { proxy.scrollTo("proc", anchor: .bottom) }
            }
        }
    }

    var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "waveform.circle.fill").font(.system(size: 60))
                .foregroundStyle(LinearGradient(colors: [accent.opacity(0.6), accentL.opacity(0.3)],
                                               startPoint: .top, endPoint: .bottom))
            Text("Hi! I'm ÁRIA").font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.8))
            Text("I can control your Mac by voice.\nSay a command:")
                .font(.system(size: 13)).foregroundColor(.white.opacity(0.35))
                .multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(["Open Safari",
                         "Set the volume to 50",
                         "Take a screenshot",
                         "Search Google for news",
                         "Play music"], id: \.self) { ex in
                    HStack(spacing: 8) {
                        Image(systemName: "mic.fill").font(.system(size: 10))
                            .foregroundColor(accent.opacity(0.7))
                        Text("\u{201C}\(ex)\u{201D}").font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.4))
                    }
                }
            }
            .padding(14).background(.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .frame(maxWidth: .infinity).padding(.vertical, 30)
    }

    var processingIndicator: some View {
        HStack(spacing: 8) {
            TypingDots()
            Text("Processando com \(ollama.selectedModel)...")
                .font(.system(size: 12)).foregroundColor(.white.opacity(0.4))
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Bottom Panel
    var bottomPanel: some View {
        VStack(spacing: 0) {
            if voice.isListening && !voice.transcribedText.isEmpty {
                Text(voice.transcribedText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.horizontal, 20).padding(.top, 12)
                    .lineLimit(2).multilineTextAlignment(.center)
            }
            if !router.lastResult.isEmpty {
                Text(router.lastResult)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(router.lastResult.hasPrefix("✅") ? Color(hex: "22C55E") :
                                     Color(hex: "FBBF24"))
                    .padding(.horizontal, 20).padding(.top, 6)
                    .lineLimit(3).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 24) {
                Spacer()
                clearButton
                micButton
                stopButton
                Spacer()
            }.padding(.vertical, 22)
            Text(statusText)
                .font(.system(size: 11)).foregroundColor(.white.opacity(0.25))
                .padding(.bottom, 14)
        }
        .background(.black.opacity(0.2))
    }

    var micButton: some View {
        ZStack {
            if voice.isListening {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .stroke(micRed.opacity(0.12 - Double(i)*0.03), lineWidth: 2)
                        .frame(width: CGFloat(80 + i*26), height: CGFloat(80 + i*26))
                        .scaleEffect(pulseScale)
                        .animation(.easeInOut(duration: 1.2).repeatForever().delay(Double(i)*0.3),
                                   value: pulseScale)
                }
            }
            Circle()
                .stroke(voice.isListening ? micRed.opacity(Double(voice.audioLevel)*0.8+0.3)
                                          : accent.opacity(glowOpacity), lineWidth: 2.5)
                .frame(width: 82, height: 82)
            Button(action: handleMicTap) {
                ZStack {
                    Circle()
                        .fill(voice.isListening
                            ? LinearGradient(colors: [micRed, Color(hex: "B91C1C")],
                                             startPoint: .top, endPoint: .bottom)
                            : LinearGradient(colors: [accent, Color(hex: "5B21B6")],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(width: 72, height: 72)
                        .shadow(color: (voice.isListening ? micRed : accent).opacity(0.5), radius: 16)
                    Image(systemName: voice.isListening ? "waveform" : "mic.fill")
                        .font(.system(size: 26)).foregroundColor(.white)
                        .scaleEffect(voice.isListening ? 1.1 : 1.0)
                        .animation(.spring(response: 0.3), value: voice.isListening)
                }
            }
            .buttonStyle(.plain)
            .disabled(isProcessing)
        }
    }

    var clearButton: some View {
        Button(action: { messages.removeAll(); router.lastAction = ""; router.lastResult = "" }) {
            Image(systemName: "trash").font(.system(size: 16))
                .foregroundColor(.white.opacity(0.25))
                .frame(width: 40, height: 40).background(.white.opacity(0.05)).clipShape(Circle())
        }.buttonStyle(.plain).help("Clear")
    }

    var stopButton: some View {
        Button(action: { tts.stopSpeaking() }) {
            Image(systemName: tts.isSpeaking ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 16))
                .foregroundColor(tts.isSpeaking ? accentL : .white.opacity(0.25))
                .frame(width: 40, height: 40).background(.white.opacity(0.05)).clipShape(Circle())
        }.buttonStyle(.plain).help("Stop speaking")
    }

    var settingsPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Settings").font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
            VStack(alignment: .leading, spacing: 5) {
                Text("Ollama model").font(.system(size: 11)).foregroundColor(.white.opacity(0.5))
                Picker("", selection: $ollama.selectedModel) {
                    if ollama.availableModels.isEmpty {
                        Text(ollama.selectedModel).tag(ollama.selectedModel)
                    } else {
                        ForEach(ollama.availableModels, id: \.self) { Text($0).tag($0) }
                    }
                }.pickerStyle(.menu).labelsHidden()
            }
            Divider().opacity(0.2)
            ForEach(["Safari", "WhatsApp", "Telegram", "Chrome"], id: \.self) { appName in
                Button("Test — \(appName)") {
                    showSettings = false
                    Task {
                        let r = appAgent().open(appName)
                        router.debugLog.append("🧪 \(appName): \(r)")
                        showDebug = true
                    }
                }.font(.system(size: 12)).foregroundColor(accentL).buttonStyle(.plain)
            }
            Button("Check connection") {
                Task { await ollama.checkConnection() }
            }.font(.system(size: 12)).foregroundColor(accentL).buttonStyle(.plain)
        }
        .padding(16).frame(width: 240).background(Color(hex: "14101F"))
    }

    // MARK: - Logic
    private func setupVoice() {
        voice.onTranscriptionComplete = { [self] text in
            Task { @MainActor in await sendToAI(text) }
        }
    }

    private func handleMicTap() {
        if tts.isSpeaking { tts.stopSpeaking() }
        voice.toggleListening()
        statusText = voice.isListening ? "Listening... speak now" : "Tap the microphone to speak"
    }

    private func sendToAI(_ userText: String) async {
        // Guarda de reentrância: se uma cadeia já está em execução, ignora o novo
        // comando para não rodar dois process() concorrentes no mesmo router
        // (eles disputariam clipboard, app em foco e eventos de teclado sintéticos).
        // Seguro: @MainActor → o check e o set rodam antes do 1º await.
        guard !isProcessing else { return }
        messages.append(ChatMessage(role: "user", content: userText))
        isProcessing = true
        statusText = "Thinking..."

        do {
            let rawLLM = try await ollama.chat(history: messages)
            let spoken = await router.process(rawLLM)
            messages.append(ChatMessage(role: "assistant", content: spoken))
            tts.speak(spoken)
            statusText = "Tap the microphone to speak"
        } catch {
            let msg = "Erro ao conectar com o Ollama."
            messages.append(ChatMessage(role: "assistant", content: msg, isError: true))
            statusText = "Error — check that Ollama is running"
        }
        isProcessing = false
    }

    private func startAnimations() {
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
            pulseScale  = 1.15
            glowOpacity = 0.7
        }
    }

    private func actionIcon(_ action: String) -> String {
        switch action {
        case let a where a.contains("app"):  return "app.badge.fill"
        case let a where a.contains("vol"):  return "speaker.wave.2.fill"
        case let a where a.contains("screen"): return "camera.fill"
        case let a where a.contains("url") || a.contains("buscar"): return "globe"
        case let a where a.contains("musi") || a.contains("play"): return "music.note"
        case let a where a.contains("shell"): return "terminal.fill"
        default: return "bolt.fill"
        }
    }

    private func appAgent() -> AppAgent { AppAgent() }
}

// MARK: - Message Bubble
struct MessageBubble: View {
    let message: ChatMessage
    private let accent  = Color(hex: "7C3AED")
    private let accentL = Color(hex: "A78BFA")
    var isUser: Bool { message.role == "user" }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if isUser { Spacer(minLength: 60) }
            if !isUser {
                ZStack {
                    Circle().fill(accent.opacity(0.2)).frame(width: 28, height: 28)
                    Text("Ā").font(.system(size: 12, weight: .black)).foregroundColor(accentL)
                }
            }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 3) {
                Text(message.content)
                    .font(.system(size: 13))
                    .foregroundColor(message.isError ? Color(hex: "FCA5A5") : .white.opacity(0.85))
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(isUser
                        ? LinearGradient(colors: [accent, Color(hex: "5B21B6")],
                                         startPoint: .topLeading, endPoint: .bottomTrailing)
                        : LinearGradient(colors: [.white.opacity(0.08), .white.opacity(0.05)],
                                         startPoint: .top, endPoint: .bottom))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16)
                        .stroke(isUser ? .clear : Color.white.opacity(0.07), lineWidth: 1))
                Text(message.timestamp, style: .time)
                    .font(.system(size: 9)).foregroundColor(.white.opacity(0.2)).padding(.horizontal, 4)
            }
            if !isUser { Spacer(minLength: 60) }
        }
    }
}

// MARK: - Typing Dots
struct TypingDots: View {
    @State private var phase = 0
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle().fill(Color(hex: "A78BFA")).frame(width: 5, height: 5)
                    .scaleEffect(phase == i ? 1.4 : 0.8)
                    .animation(.easeInOut(duration: 0.4).repeatForever().delay(Double(i)*0.15), value: phase)
            }
        }
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 0.45, repeats: true) { _ in
                phase = (phase + 1) % 3
            }
        }
    }
}
