import AppKit
import Foundation

/// Abre, fecha e gerencia aplicativos — suporta qualquer app instalado no Mac
final class AppAgent {

    // ── Bundle IDs conhecidos (fast-path) ─────────────────────────────────
    private static let bundleMap: [String: String] = [
        "safari": "com.apple.Safari",
        "chrome": "com.google.Chrome",
        "google chrome": "com.google.Chrome",
        "firefox": "org.mozilla.firefox",
        "arc": "company.thebrowser.Browser",
        "finder": "com.apple.finder",
        "terminal": "com.apple.Terminal",
        "iterm": "com.googlecode.iterm2",
        "iterm2": "com.googlecode.iterm2",
        "vscode": "com.microsoft.VSCode",
        "visual studio code": "com.microsoft.VSCode",
        "code": "com.microsoft.VSCode",
        "xcode": "com.apple.dt.Xcode",
        "spotify": "com.spotify.client",
        "music": "com.apple.Music",
        "musica": "com.apple.Music",
        "notes": "com.apple.Notes",
        "notas": "com.apple.Notes",
        "calculator": "com.apple.calculator",
        "calculadora": "com.apple.calculator",
        "calendar": "com.apple.iCal",
        "agenda": "com.apple.iCal",
        "mail": "com.apple.mail",
        "messages": "com.apple.MobileSMS",
        "mensagens": "com.apple.MobileSMS",
        "facetime": "com.apple.FaceTime",
        "photos": "com.apple.Photos",
        "fotos": "com.apple.Photos",
        "maps": "com.apple.Maps",
        "mapas": "com.apple.Maps",
        "slack": "com.tinyspeck.slackmacgap",
        "telegram": "com.tdesktop.Telegram",
        "tekegram": "com.tdesktop.Telegram",
        "telegran": "com.tdesktop.Telegram",
        "teleg": "com.tdesktop.Telegram",
        "whatsapp": "net.whatsapp.WhatsApp",
        "watsapp": "net.whatsapp.WhatsApp",
        "whatsap": "net.whatsapp.WhatsApp",
        "zap": "net.whatsapp.WhatsApp",
        "wpp": "net.whatsapp.WhatsApp",
        "zoom": "us.zoom.xos",
        "system preferences": "com.apple.systempreferences",
        "system settings": "com.apple.systempreferences",
        "ajustes": "com.apple.systempreferences",
        "configuracoes": "com.apple.systempreferences",
        "activity monitor": "com.apple.ActivityMonitor",
        "monitor de atividade": "com.apple.ActivityMonitor",
        "obs": "com.obsproject.obs-studio",
        "figma": "com.figma.Desktop",
        "notion": "notion.id",
        "discord": "com.hnc.Discord",
        "microsoft word": "com.microsoft.Word",
        "word": "com.microsoft.Word",
        "excel": "com.microsoft.Excel",
        "powerpoint": "com.microsoft.Powerpoint",
        "outlook": "com.microsoft.Outlook",
        "teams": "com.microsoft.teams",
        "vlc": "org.videolan.vlc",
        "preview": "com.apple.Preview",
        "visualizador": "com.apple.Preview",
        "pages": "com.apple.iWork.Pages",
        "numbers": "com.apple.iWork.Numbers",
        "keynote": "com.apple.iWork.Keynote",
        "shortcuts": "com.apple.shortcuts",
        "atalhos": "com.apple.shortcuts",
        "automator": "com.apple.automator",
        "xld": "jp.tmkk.XLD",
        "tor": "org.torproject.torbrowser",
        "1password": "com.1password.1password",
        "affinity photo": "com.seriflabs.affinityphoto",
        "affinity designer": "com.seriflabs.affinitydesigner",
        "cursor": "com.todesktop.230313mzl4w4u92",
        "warp": "dev.warp.Warp-Stable",
    ]

    // ── Cache de apps instalados (escaneado uma vez) ───────────────────────
    private static var _appCache: [(name: String, path: String)] = []
    private static var _cacheBuilt = false
    private static let _cacheLock = NSLock()

    private static func buildAppCache() {
        // Lock: route() roda fora da main thread; protege contra build concorrente
        // do cache estático (check-then-set não-atômico).
        _cacheLock.lock(); defer { _cacheLock.unlock() }
        guard !_cacheBuilt else { return }
        _cacheBuilt = true
        let searchDirs = [
            "/Applications",
            "\(NSHomeDirectory())/Applications",
            "/System/Applications",
            "/System/Applications/Utilities",
            "/Applications/Utilities",
        ]
        var results: [(String, String)] = []
        for dir in searchDirs {
            guard let items = try? FileManager.default.contentsOfDirectory(atPath: dir) else { continue }
            for item in items where item.hasSuffix(".app") {
                let appName = String(item.dropLast(4)) // remove ".app"
                let path = "\(dir)/\(item)"
                results.append((appName, path))
            }
        }
        _appCache = results
    }

    // ── Fuzzy matching ────────────────────────────────────────────────────
    /// Distância de Levenshtein simplificada para strings curtas
    private static func levenshtein(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var dp = Array(0...b.count)
        for i in 1...a.count {
            var prev = i
            for j in 1...b.count {
                let cost = a[i-1] == b[j-1] ? 0 : 1
                let cur = min(dp[j]+1, min(prev+1, dp[j-1]+cost))
                dp[j-1] = prev
                prev = cur
            }
            dp[b.count] = prev
        }
        return dp[b.count]
    }

    /// Encontra o melhor app pelo nome (fuzzy)
    private static func findAppPath(for query: String) -> String? {
        buildAppCache()
        let q = query.lowercased()

        // 1. Correspondência exata (case-insensitive)
        if let exact = _appCache.first(where: { $0.name.lowercased() == q }) {
            return exact.path
        }

        // 2. Contém a query
        if let contains = _appCache.first(where: { $0.name.lowercased().contains(q) }) {
            return contains.path
        }

        // 3. Query contém o nome (ex: "whatsapp" contém "what")
        if let rev = _appCache.first(where: { q.contains($0.name.lowercased()) }) {
            return rev.path
        }

        // 4. Levenshtein ≤ 3 (tolera erros de digitação/transcrição de voz)
        let scored = _appCache.map { (lev: levenshtein(q, $0.name.lowercased()), path: $0.path, name: $0.name) }
        if let best = scored.min(by: { $0.lev < $1.lev }), best.lev <= 3 {
            return best.path
        }

        return nil
    }

    // ── Verificação de estado (para workflows confiáveis) ──────────────────

    /// O app está em execução? (por bundle id quando conhecido, senão por nome)
    static func isRunning(named name: String, bundle: String?) -> Bool {
        let apps = NSWorkspace.shared.runningApplications
        if let b = bundle, apps.contains(where: { $0.bundleIdentifier == b }) { return true }
        let n = name.lowercased()
        guard n.count >= 2 else { return false }
        return apps.contains {
            (($0.localizedName ?? "").lowercased().contains(n)) ||
            ((($0.bundleURL?.deletingPathExtension().lastPathComponent) ?? "").lowercased().contains(n))
        }
    }

    /// Traz o app para frente (necessário para o próximo passo do workflow agir sobre ele)
    private func activate(name: String, bundle: String?) {
        let apps = NSWorkspace.shared.runningApplications
        let app = (bundle.flatMap { b in apps.first { $0.bundleIdentifier == b } })
            ?? apps.first { ($0.localizedName ?? "").lowercased().contains(name.lowercased()) }
        app?.activate(options: [.activateIgnoringOtherApps])
    }

    // ── API pública ───────────────────────────────────────────────────────
    @discardableResult
    func open(_ rawName: String) -> String {
        let name = rawName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return "⚠️ Nome do app não informado" }
        let key = name.lowercased().replacingOccurrences(of: ".app", with: "")
        let bid = Self.bundleMap[key]

        // Fast-path: já está rodando → só ativa (workflow segue imediatamente)
        if Self.isRunning(named: name, bundle: bid) {
            activate(name: name, bundle: bid)
            return "✅ \(name) já estava aberto"
        }

        var launched = false
        var via = name

        // 1. Caminho direto via bundle map (mais confiável)
        if let bid, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid),
           !runOpen([url.path]).lowercased().contains("error") {
            launched = true
        }
        // 2. open -a com nome exato (argv direto, sem shell)
        if !launched {
            let r = runOpen(["-a", name])
            if !r.lowercased().contains("unable") && !r.lowercased().contains("error") { launched = true }
        }
        // 3. caminho direto em /Applications
        if !launched {
            let p = "/Applications/\(name).app"
            if FileManager.default.fileExists(atPath: p), !runOpen([p]).lowercased().contains("error") {
                launched = true
            }
        }
        // 4. nome capitalizado (corrige casing do LLM)
        if !launched {
            let cap = name.prefix(1).uppercased() + name.dropFirst().lowercased()
            let r = runOpen(["-a", cap])
            if !r.lowercased().contains("unable") && !r.lowercased().contains("error") { launched = true; via = cap }
        }
        // 5. escaneamento dinâmico + fuzzy match
        if !launched, let path = Self.findAppPath(for: name),
           !runOpen([path]).lowercased().contains("error") {
            launched = true; via = path
        }
        // 6. mdfind (nome escapado para o grep)
        if !launched {
            let safeName = name.replacingOccurrences(of: "\"", with: "")
                .replacingOccurrences(of: "$", with: "").replacingOccurrences(of: "`", with: "")
            let mdf = shell("/usr/bin/mdfind 'kMDItemContentType == \"com.apple.application-bundle\"' 2>/dev/null | /usr/bin/grep -i \"\(safeName)\" | head -1").trimmingCharacters(in: .whitespacesAndNewlines)
            if !mdf.isEmpty, !runOpen([mdf]).lowercased().contains("error") { launched = true; via = mdf }
        }
        // 7. AppleScript como último recurso (nome escapado)
        if !launched {
            let escName = name.replacingOccurrences(of: "\\", with: "\\\\")
                              .replacingOccurrences(of: "\"", with: "\\\"")
            _ = osascript("tell application \"\(escName)\" to activate")
        }

        // VERIFICAÇÃO: espera o app ficar realmente em execução antes de concluir,
        // para que a PRÓXIMA etapa do workflow possa agir sobre ele com segurança.
        let ready = waitUntil(timeoutMs: 4500, pollMs: 150) { Self.isRunning(named: name, bundle: bid) }
        if ready {
            activate(name: name, bundle: bid)
            return "✅ Aberto: \(via)"
        }
        return launched ? "✅ Aberto: \(via)" : "⚠️ Não foi possível abrir \(name)"
    }

    @discardableResult
    func close(_ rawName: String) -> String {
        let name = rawName.trimmingCharacters(in: .whitespaces)
        let escapedName = name.replacingOccurrences(of: "\\", with: "\\\\")
                              .replacingOccurrences(of: "\"", with: "\\\"")
        let r = osascript("tell application \"\(escapedName)\" to quit")
        return r.isEmpty ? "✅ Fechado: \(name)" : "⚠️ \(r)"
    }

    /// true se o nome corresponde a um app conhecido (bundle map) ou instalado (scan).
    func isKnownApp(_ rawName: String) -> Bool {
        let key = rawName.lowercased().trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ".app", with: "")
        if Self.bundleMap[key] != nil { return true }
        return Self.findAppPath(for: rawName) != nil
    }

    /// Abre via /usr/bin/open passando argumentos como argv (sem shell) — evita
    /// quebra/injeção quando o nome contém aspas, espaços ou metacaracteres.
    @discardableResult
    private func runOpen(_ args: [String]) -> String {
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = args
        let outPipe = Pipe(); let errPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = errPipe
        try? task.run()
        task.waitUntilExit()
        let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (out + err).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func listRunning() -> [String] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { $0.localizedName }
    }

    func listAllInstalled() -> [String] {
        Self.buildAppCache()
        return Self.appCache.map { $0.name }.sorted()
    }

    private static var appCache: [(name: String, path: String)] {
        buildAppCache()
        return _appCache
    }
}
