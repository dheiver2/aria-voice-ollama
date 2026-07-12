import Foundation

// Helpers globais usados por todos os agentes

@discardableResult
func shell(_ cmd: String) -> String {
    let task = Process()
    let pipe = Pipe()
    task.launchPath = "/bin/zsh"
    task.arguments  = ["-c", cmd]
    task.standardOutput = pipe
    task.standardError  = Pipe()
    try? task.run()
    task.waitUntilExit()
    return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
}

/// Espera (poll) até a condição ser verdadeira ou estourar o timeout.
/// Use SOMENTE fora da main thread (faz Thread.sleep). Retorna true se satisfez a condição.
@discardableResult
func waitUntil(timeoutMs: Int = 3500, pollMs: Int = 120, _ condition: () -> Bool) -> Bool {
    var waited = 0
    if condition() { return true }
    while waited < timeoutMs {
        Thread.sleep(forTimeInterval: Double(pollMs) / 1000.0)
        waited += pollMs
        if condition() { return true }
    }
    return false
}

@discardableResult
func osascript(_ script: String) -> String {
    // Usa /usr/bin/osascript via Process — mais confiável para Automation TCC
    let task = Process()
    let pipe = Pipe()
    let errPipe = Pipe()
    task.launchPath = "/usr/bin/osascript"
    task.arguments  = ["-e", script]
    task.standardOutput = pipe
    task.standardError  = errPipe
    try? task.run()
    task.waitUntilExit()
    let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    if task.terminationStatus != 0 && !err.isEmpty {
        return err.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return out.trimmingCharacters(in: .whitespacesAndNewlines)
}
