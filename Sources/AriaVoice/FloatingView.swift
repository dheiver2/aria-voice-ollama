import SwiftUI

struct FloatingView: View {
    @ObservedObject var vm: FloatingViewModel

    var body: some View {
        ZStack {
            // Glass background
            RoundedRectangle(cornerRadius: 24)
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: 24)
                .fill(Color(hex: "0A0814").opacity(0.6))
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)

            VStack(spacing: 0) {
                // Top bar
                topBar

                // Content area
                contentArea

                // Bottom: orb + hint
                bottomBar
            }
            .padding(.vertical, 4)
        }
        .shadow(color: .black.opacity(0.5), radius: 40, x: 0, y: 20)
        .frame(width: 440)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: vm.responseText)
    }

    // MARK: - Top bar
    var topBar: some View {
        HStack(spacing: 8) {
            // Logo
            ZStack {
                Circle().fill(Color(hex: "7C3AED").opacity(0.25)).frame(width: 26, height: 26)
                Text("Ā").font(.system(size: 13, weight: .black)).foregroundColor(Color(hex: "A78BFA"))
            }
            Text("ÁRIA").font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.9))
            Spacer()

            // Model badge
            if !vm.modelName.isEmpty {
                Text(vm.modelName).font(.system(size: 9, weight: .medium))
                    .foregroundColor(.white.opacity(0.35))
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(.white.opacity(0.07))
                    .clipShape(Capsule())
            }

            // Close
            Button(action: vm.close) {
                Image(systemName: "xmark").font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.3))
                    .frame(width: 24, height: 24)
                    .background(.white.opacity(0.06))
                    .clipShape(Circle())
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    // MARK: - Content area
    @ViewBuilder
    var contentArea: some View {
        VStack(spacing: 10) {
            // Transcription
            if !vm.transcription.isEmpty {
                Text(vm.transcription)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 24)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else if vm.orbState == .idle {
                Text(vm.hint)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.3))
                    .multilineTextAlignment(.center)
            }

            // Streaming response
            if !vm.responseText.isEmpty {
                ScrollView {
                    Text(vm.responseText)
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundColor(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .frame(maxWidth: .infinity)
                }
                .frame(maxHeight: 120)
                .transition(.opacity)
            }

            // Processing label
            if vm.orbState == .processing && vm.responseText.isEmpty {
                HStack(spacing: 6) {
                    StreamingDots()
                    Text("Processando...").font(.system(size: 12)).foregroundColor(.white.opacity(0.4))
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, vm.responseText.isEmpty ? 4 : 12)
        .animation(.easeInOut(duration: 0.3), value: vm.responseText)
        .animation(.easeInOut(duration: 0.2), value: vm.transcription)
    }

    // MARK: - Bottom bar (orb)
    var bottomBar: some View {
        VStack(spacing: 6) {
            Divider().opacity(0.08)
            HStack(spacing: 20) {
                // History button
                Button(action: vm.showHistory) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(vm.historyVisible ? 0.8 : 0.25))
                }
                .buttonStyle(.plain)

                // ORB (main tap target)
                Button(action: vm.handleOrbTap) {
                    OrbView(state: vm.orbState, audioLevel: vm.audioLevel)
                        .frame(width: 80, height: 80)
                }
                .buttonStyle(.plain)
                .disabled(vm.orbState == .processing)

                // Settings
                Button(action: vm.showSettings) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.25))
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 10)

            Text(stateHint)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.2))
                .padding(.bottom, 10)
        }
    }

    private var stateHint: String {
        switch vm.orbState {
        case .idle:       return "Toque para falar  •  ⌥Space"
        case .listening:  return "Ouvindo... pare de falar para enviar"
        case .processing: return "Processando com \(vm.modelName)..."
        case .speaking:   return "Toque para parar"
        }
    }
}

// MARK: - Streaming Dots
struct StreamingDots: View {
    @State private var phase = 0
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { i in
                Circle().fill(Color(hex: "A78BFA")).frame(width: 4, height: 4)
                    .scaleEffect(phase == i ? 1.5 : 0.8)
                    .animation(.easeInOut(duration: 0.35).repeatForever().delay(Double(i) * 0.12),
                               value: phase)
            }
        }
        .onAppear { Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in phase = (phase+1)%3 } }
    }
}
