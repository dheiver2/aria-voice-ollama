import Foundation
import AppKit

/// Controla Music, Spotify, vídeo no navegador (YouTube/HTML5) e mídia do sistema
final class MediaAgent {

    enum MediaApp { case music, spotify, system }

    private func activeMedia() -> MediaApp {
        let running = shell("osascript -e 'tell application \"System Events\" to get name of every process whose background only is false'")
        if running.lowercased().contains("spotify") { return .spotify }
        if running.lowercased().contains("music")   { return .music }
        return .system
    }

    // MARK: - Navegadores (player de vídeo: YouTube, HTML5, etc.)

    private static let browsers: [(name: String, bundle: String)] = [
        ("Google Chrome",   "com.google.Chrome"),
        ("Safari",          "com.apple.Safari"),
        ("Arc",             "company.thebrowser.Browser"),
        ("Microsoft Edge",  "com.microsoft.edgemac"),
        ("Brave Browser",   "com.brave.Browser"),
        ("Firefox",         "org.mozilla.firefox"),
    ]

    /// Navegador em primeiro plano (provável player de vídeo ativo)
    private func frontmostBrowser() -> String? {
        guard let front = NSWorkspace.shared.runningApplications.first(where: { $0.isActive }),
              let name = front.localizedName else { return nil }
        return Self.browsers.first(where: { $0.name == name })?.name
    }

    /// Qualquer navegador em execução (o frontmost tem prioridade)
    private func anyRunningBrowser() -> String? {
        if let f = frontmostBrowser() { return f }
        let apps = NSWorkspace.shared.runningApplications
        return Self.browsers.first(where: { b in apps.contains { $0.bundleIdentifier == b.bundle } })?.name
    }

    /// Envia uma tecla ao player do navegador (atalhos do YouTube: k=play/pause,
    /// m=mudo, f=tela cheia, j=-10s, l=+10s, Shift+N=próximo).
    @discardableResult
    func browserKey(_ key: String, shift: Bool = false, browser: String? = nil) -> Bool {
        guard let b = browser ?? anyRunningBrowser() else { return false }
        let mod = shift ? " using {shift down}" : ""
        let script = """
        tell application "\(b)" to activate
        delay 0.15
        tell application "System Events" to tell process "\(b)" to keystroke "\(key)"\(mod)
        """
        _ = osascript(script)
        return true
    }

    /// Controla o player de vídeo do navegador (YouTube/HTML5).
    @discardableResult
    func controlVideo(_ cmd: String) -> String {
        guard let b = anyRunningBrowser() else {
            return "⚠️ Nenhum navegador aberto para controlar o vídeo."
        }
        switch cmd.lowercased() {
        case "play", "pause", "pausar", "tocar", "playpause", "play_pause", "toggle":
            browserKey("k", browser: b); return "✅ Play/pause no vídeo (\(b))"
        case "mute", "mudo", "silenciar", "desmutar":
            browserKey("m", browser: b); return "✅ Mudo no vídeo (\(b))"
        case "fullscreen", "tela_cheia", "telacheia", "cheia":
            browserKey("f", browser: b); return "✅ Tela cheia (\(b))"
        case "avancar", "forward", "frente", "adiantar":
            browserKey("l", browser: b); return "✅ Avançou 10s (\(b))"
        case "voltar", "back", "retroceder", "atras":
            browserKey("j", browser: b); return "✅ Voltou 10s (\(b))"
        case "proximo", "next", "proxima":
            browserKey("n", shift: true, browser: b); return "✅ Próximo vídeo (\(b))"
        default:
            browserKey("k", browser: b); return "✅ Play/pause no vídeo (\(b))"
        }
    }

    @discardableResult
    func play() -> String {
        // Se um navegador está em primeiro plano, provavelmente é um vídeo (YouTube/HTML5):
        // o atalho "k" dá play/pause no player da web.
        if let b = frontmostBrowser() {
            browserKey("k", browser: b)
            return "✅ Play no vídeo (\(b))"
        }
        switch activeMedia() {
        case .spotify: osascript("tell application \"Spotify\" to play")
        case .music:   osascript("tell application \"Music\" to play")
        case .system:  osascript("tell application \"Music\" to play")
        }
        return "✅ Reproduzindo"
    }

    @discardableResult
    func pause() -> String {
        if let b = frontmostBrowser() {
            browserKey("k", browser: b)
            return "✅ Pausado (\(b))"
        }
        switch activeMedia() {
        case .spotify: osascript("tell application \"Spotify\" to pause")
        case .music:   osascript("tell application \"Music\" to pause")
        case .system:
            // Sem app de música em foco: tenta o player do navegador, se houver
            if anyRunningBrowser() != nil { browserKey("k") }
        }
        return "✅ Pausado"
    }

    @discardableResult
    func next() -> String {
        switch activeMedia() {
        case .spotify: osascript("tell application \"Spotify\" to next track")
        case .music:   osascript("tell application \"Music\" to next track")
        case .system:
            osascript("""
                tell application "System Events"
                    key code 17 using {}
                end tell
            """)
        }
        return "✅ Próxima faixa"
    }

    @discardableResult
    func previous() -> String {
        switch activeMedia() {
        case .spotify: osascript("tell application \"Spotify\" to previous track")
        case .music:   osascript("tell application \"Music\" to back track")
        case .system:
            osascript("""
                tell application "System Events"
                    key code 18 using {}
                end tell
            """)
        }
        return "✅ Faixa anterior"
    }

    func nowPlaying() -> String {
        let r = osascript("""
            tell application "Music"
                if player state is playing then
                    return name of current track & " - " & artist of current track
                end if
            end tell
        """)
        if !r.isEmpty { return r }
        return "Nenhuma mídia tocando"
    }

    @discardableResult
    func setVolume(_ v: Int) -> String {
        osascript("set volume output volume \(max(0,min(100,v)))")
        return "✅ Volume: \(v)%"
    }
}
