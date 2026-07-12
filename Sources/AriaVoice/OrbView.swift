import SwiftUI

enum OrbState {
    case idle, listening, processing, speaking
}

struct OrbView: View {
    var state: OrbState
    var audioLevel: Float = 0

    @State private var rotation: Double = 0
    @State private var pulse: CGFloat  = 1.0
    @State private var shimmer: Double = 0

    var body: some View {
        ZStack {
            // Outer glow ring
            Circle()
                .fill(outerColor.opacity(0.15))
                .frame(width: 100 + CGFloat(audioLevel) * 40, height: 100 + CGFloat(audioLevel) * 40)
                .blur(radius: 12)
                .animation(.easeOut(duration: 0.1), value: audioLevel)

            // Animated blob background
            ZStack {
                ForEach(0..<4, id: \.self) { i in
                    Ellipse()
                        .fill(blobColor(i))
                        .frame(width: blobSize(i), height: blobSize(i) * 0.85)
                        .blur(radius: 14)
                        .rotationEffect(.degrees(rotation + Double(i) * 90))
                        .scaleEffect(pulse)
                        .opacity(0.75)
                }
            }
            .frame(width: 80, height: 80)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(
                        LinearGradient(colors: [.white.opacity(0.35), .clear],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1
                    )
            )
            .shadow(color: outerColor.opacity(0.5), radius: 16)

            // Center icon
            Group {
                switch state {
                case .idle:
                    Image(systemName: "waveform")
                        .font(.system(size: 22, weight: .light))
                        .foregroundColor(.white.opacity(0.7))
                case .listening:
                    Image(systemName: "waveform")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(.white)
                        .scaleEffect(1 + CGFloat(audioLevel) * 0.4)
                        .animation(.easeOut(duration: 0.08), value: audioLevel)
                case .processing:
                    Image(systemName: "sparkles")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.white)
                        .rotationEffect(.degrees(shimmer))
                case .speaking:
                    Image(systemName: "speaker.wave.3.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white)
                        .scaleEffect(pulse)
                }
            }
        }
        .frame(width: 100, height: 100)
        .onAppear { startAnimations() }
        .onChange(of: state) { _ in startAnimations() }
    }

    // MARK: - Colors per state
    private var outerColor: Color {
        switch state {
        case .idle:       return Color(hex: "7C3AED")
        case .listening:  return Color(hex: "EF4444")
        case .processing: return Color(hex: "F59E0B")
        case .speaking:   return Color(hex: "10B981")
        }
    }

    private func blobColor(_ i: Int) -> Color {
        switch state {
        case .idle:
            return [Color(hex: "7C3AED"), Color(hex: "4F46E5"),
                    Color(hex: "A78BFA"), Color(hex: "6D28D9")][i]
        case .listening:
            return [Color(hex: "EF4444"), Color(hex: "DC2626"),
                    Color(hex: "F87171"), Color(hex: "B91C1C")][i]
        case .processing:
            return [Color(hex: "F59E0B"), Color(hex: "D97706"),
                    Color(hex: "FBBF24"), Color(hex: "B45309")][i]
        case .speaking:
            return [Color(hex: "10B981"), Color(hex: "059669"),
                    Color(hex: "34D399"), Color(hex: "047857")][i]
        }
    }

    private func blobSize(_ i: Int) -> CGFloat {
        let base: CGFloat = 60
        let offsets: [CGFloat] = [0, 8, 4, 12]
        return base + offsets[i]
    }

    // MARK: - Animations
    private func startAnimations() {
        withAnimation(.linear(duration: rotationSpeed).repeatForever(autoreverses: false)) {
            rotation = 360
        }
        withAnimation(.easeInOut(duration: pulseSpeed).repeatForever(autoreverses: true)) {
            pulse = pulseRange
        }
        if state == .processing {
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                shimmer = 360
            }
        }
    }

    private var rotationSpeed: Double {
        switch state {
        case .idle: return 6
        case .listening: return 2
        case .processing: return 1.5
        case .speaking: return 3
        }
    }

    private var pulseSpeed: Double {
        switch state {
        case .idle: return 2.5
        case .listening: return 0.6
        case .processing: return 0.8
        case .speaking: return 0.5
        }
    }

    private var pulseRange: CGFloat {
        switch state {
        case .idle: return 1.05
        case .listening: return 1.15
        case .processing: return 1.08
        case .speaking: return 1.12
        }
    }
}
