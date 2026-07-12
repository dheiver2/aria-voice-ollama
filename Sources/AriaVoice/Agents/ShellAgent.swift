import Foundation

/// Executa comandos shell com allowlist de segurança
final class ShellAgent {

    // Prefixos de comandos permitidos
    private let allowed = [
        "ls", "cat", "echo", "pwd", "whoami", "date", "df", "du",
        "open", "mkdir", "touch", "mv", "cp", "find", "grep",
        "curl", "ping", "ifconfig", "networksetup", "defaults",
        "killall", "kill", "ps", "top", "memory_pressure", "pmset",
        "osascript", "say", "screencapture", "afplay", "mdfind",
    ]

    func run(_ cmd: String) -> String {
        let trimmed = cmd.trimmingCharacters(in: .whitespaces)

        // O comando roda via /bin/zsh -c, que interpreta metacaracteres
        // (&&, |, ;, $(), `, <, >, newline). Validar só o primeiro token não basta:
        // qualquer coisa após um separador rodaria sem checagem. Rejeitamos comandos
        // que contenham encadeamento/metacaracteres de shell.
        let metachars = CharacterSet(charactersIn: "|;&$`<>()\n\r")
        if trimmed.rangeOfCharacter(from: metachars) != nil {
            return "⛔ Comando bloqueado por segurança: encadeamento/metacaracteres não permitidos"
        }

        let base = trimmed.components(separatedBy: " ").first ?? ""

        guard allowed.contains(base) || trimmed.hasPrefix("open ") else {
            return "⛔ Comando bloqueado por segurança: \(base)"
        }

        let out = shell(trimmed)
        let result = out.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? "✅ Executado" : result
    }

    func createFolder(_ path: String) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        do {
            try FileManager.default.createDirectory(atPath: expanded, withIntermediateDirectories: true)
            return "✅ Pasta criada: \(path)"
        } catch {
            return "⚠️ Erro: \(error.localizedDescription)"
        }
    }
}
