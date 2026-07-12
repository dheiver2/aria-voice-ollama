import Foundation
import AppKit

/// Controla volume, brilho, screenshot, notificações, bateria
final class SystemAgent {

    // MARK: Volume

    @discardableResult
    func setVolume(_ level: Int) -> String {
        let v = max(0, min(100, level))
        // osascript é mais confiável que NSAppleScript para permissões
        let r = osascript("set volume output volume \(v)")
        return r.isEmpty ? "✅ Volume: \(v)%" : "⚠️ \(r)"
    }

    @discardableResult
    func mute(_ on: Bool) -> String {
        let script = on ? "set volume with output muted"
                       : "set volume without output muted"
        let r = osascript(script)
        return r.isEmpty ? "✅ Mudo: \(on)" : "⚠️ \(r)"
    }

    func getVolume() -> Int {
        let out = shell("osascript -e 'output volume of (get volume settings)'")
        return Int(out.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    // MARK: Brightness

    @discardableResult
    func setBrightness(_ level: Int) -> String {
        let v = max(0, min(100, level))
        // Tenta via CLI brightness se instalado
        let b1 = shell("which brightness 2>/dev/null")
        if !b1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            shell("brightness \(Double(v)/100.0)")
            return "✅ Brilho: \(v)%"
        }
        // Fallback: ddcctl ou teclas via osascript
        let script = """
        tell application "System Events"
            key code 113 using {option down, shift down}
        end tell
        """
        _ = osascript(script)
        return "✅ Brilho ajustado (instale 'brightness' via Homebrew para controle preciso)"
    }

    // MARK: Screenshot

    @discardableResult
    func screenshot(interactive: Bool = false) -> String {
        let desktop = NSHomeDirectory() + "/Desktop"
        let ts = Int(Date().timeIntervalSince1970)
        let path = "\(desktop)/aria_\(ts).png"
        let flag = interactive ? "-i" : "-x"
        shell("/usr/sbin/screencapture \(flag) '\(path)'")
        return "✅ Screenshot salvo: ~/Desktop/aria_\(ts).png"
    }

    // MARK: Notification

    @discardableResult
    func notify(title: String, body: String) -> String {
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "\\", with: "\\\\")
             .replacingOccurrences(of: "\"", with: "\\\"")
             .replacingOccurrences(of: "\r\n", with: " ")
             .replacingOccurrences(of: "\n", with: " ")
             .replacingOccurrences(of: "\r", with: " ")
        }
        let t = esc(title)
        let b = esc(body)
        let r = osascript("display notification \"\(b)\" with title \"\(t)\"")
        return r.isEmpty ? "✅ Notificação enviada" : "⚠️ \(r)"
    }

    // MARK: Battery / System Info

    func batteryInfo() -> String {
        let raw = shell("pmset -g batt")
        let lines = raw.components(separatedBy: "\n")
        let pct = lines.compactMap { l -> String? in
            guard let r = l.range(of: #"\d{1,3}%"#, options: .regularExpression) else { return nil }
            return String(l[r])
        }.first ?? "indisponível"
        return pct
    }

    func systemInfo() -> String {
        let cpu  = shell("top -l 1 -s 0 | grep 'CPU usage' | awk '{print $3}' | tr -d '%'").trimmingCharacters(in: .whitespacesAndNewlines)
        let mem  = shell("memory_pressure | grep 'System-wide' | awk -F': ' '{print $2}'").trimmingCharacters(in: .whitespacesAndNewlines)
        let bat  = batteryInfo()
        return "CPU: \(cpu)% | Memória: \(mem) | \(bat)"
    }

    // MARK: Dark / Light Mode

    @discardableResult
    func toggleDarkMode() -> String {
        let script = """
        tell application "System Events"
            tell appearance preferences
                set dark mode to not dark mode
            end tell
        end tell
        """
        let r = osascript(script)
        return r.isEmpty ? "✅ Modo escuro alternado" : "⚠️ \(r)"
    }

    // MARK: Do Not Disturb

    @discardableResult
    func setDoNotDisturb(_ on: Bool) -> String {
        // macOS Ventura+
        let val = on ? "true" : "false"
        let r = shell("defaults -currentHost write com.apple.notificationcenterui doNotDisturb -bool \(val) && killall NotificationCenter 2>/dev/null; echo ok")
        return r.contains("ok") ? "✅ Não Perturbe: \(on)" : "⚠️ Requer permissão"
    }

    // MARK: Sleep / Lock

    @discardableResult
    func lockScreen() -> String {
        shell("/System/Library/CoreServices/ScreenSaverEngine.app/Contents/MacOS/ScreenSaverEngine -background &")
        return "✅ Tela bloqueada"
    }

    @discardableResult
    func sleep() -> String {
        shell("pmset sleepnow")
        return "✅ Entrando em repouso"
    }
}
