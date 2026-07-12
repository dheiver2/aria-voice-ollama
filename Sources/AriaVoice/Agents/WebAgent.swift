import AppKit
import Foundation

/// Abre URLs e faz buscas na web
final class WebAgent {

    private let searchEngines: [String: String] = [
        "google":    "https://www.google.com/search?q=",
        "youtube":   "https://www.youtube.com/results?search_query=",
        "bing":      "https://www.bing.com/search?q=",
        "wikipedia": "https://pt.wikipedia.org/wiki/Special:Search?search=",
        "maps":      "https://maps.google.com/?q=",
    ]

    @discardableResult
    func openURL(_ raw: String) -> String {
        var str = raw.trimmingCharacters(in: .whitespaces)
        if !str.hasPrefix("http") { str = "https://" + str }
        guard let url = URL(string: str) else { return "⚠️ URL inválida: \(raw)" }
        NSWorkspace.shared.open(url)
        return "✅ Abrindo: \(str)"
    }

    @discardableResult
    func search(_ query: String, engine: String = "google") -> String {
        let base = searchEngines[engine.lowercased()] ?? searchEngines["google"]!
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        return openURL(base + encoded)
    }

    /// Abre o YouTube e TOCA o 1º resultado de `query`.
    /// Estratégia confiável (sem depender de JS do navegador): baixa o HTML da
    /// busca, extrai o `videoId` do 1º vídeo e abre direto `/watch?v=ID`, que o
    /// YouTube reproduz automaticamente.
    @discardableResult
    func playYouTube(_ query: String) -> String {
        let clean = query.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty else { return "⚠️ Diga o que tocar no YouTube." }
        let q = clean.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? clean
        let searchURL = "https://www.youtube.com/results?search_query=\(q)"

        if let vid = firstVideoId(searchURL: searchURL) {
            let watch = "https://www.youtube.com/watch?v=\(vid)"
            if let url = URL(string: watch) { NSWorkspace.shared.open(url) }
            // Settle: dá tempo do vídeo carregar/ganhar foco ANTES de um próximo passo
            // da cadeia (ex.: "toca X no youtube E coloca em tela cheia") mandar teclas
            // ao player — senão o atalho cai numa página ainda em branco. Roda no
            // worker em background, não congela a UI.
            Thread.sleep(forTimeInterval: 2.2)
            return "▶️ Tocando \"\(clean)\" no YouTube."
        }
        // Fallback: não achou o vídeo → abre a busca p/ o usuário escolher
        if let url = URL(string: searchURL) { NSWorkspace.shared.open(url) }
        return "🔎 Abri a busca de \"\(clean)\" no YouTube — diga \"dá play\" no vídeo escolhido."
    }

    /// Baixa o HTML da busca do YouTube e extrai o videoId do 1º resultado.
    private func firstVideoId(searchURL: String) -> String? {
        let ua = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " +
                 "(KHTML, like Gecko) Chrome/120 Safari/537.36"
        let task = Process()
        task.launchPath = "/usr/bin/curl"
        task.arguments = ["-s", "-A", ua, "--max-time", "6", searchURL]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        try? task.run()
        task.waitUntilExit()
        let html = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard !html.isEmpty,
              let rx = try? NSRegularExpression(pattern: #""videoId":"([A-Za-z0-9_-]{11})""#) else { return nil }
        let range = NSRange(html.startIndex..., in: html)
        guard let m = rx.firstMatch(in: html, range: range), m.numberOfRanges >= 2,
              let r = Range(m.range(at: 1), in: html) else { return nil }
        return String(html[r])
    }
}
