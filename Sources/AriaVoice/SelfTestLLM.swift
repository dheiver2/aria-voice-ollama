import Foundation

/// Teste AO VIVO do cérebro (Ollama + prompt real do OllamaService).
/// Rodar: AriaVoice --testllm   (precisa do Ollama no ar)
/// Valida o health-check (concern do "Offline") e se comandos reais viram
/// JSON de ação esperado. NÃO executa AgentRouter → zero efeito colateral.
enum SelfTestLLM {

    struct Caso { let comando: String; let esperado: [String] }  // ação(ões) que devem aparecer

    /// Extrai o objeto JSON de forma leniente (mesma ideia do router) e
    /// devolve o(s) nome(s) de ação: "acao" único ou cada item de "acoes".
    static func acoes(de raw: String) -> [String]? {
        let c = raw.replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "")
        guard let a = c.firstIndex(of: "{"), let b = c.lastIndex(of: "}"), a < b,
              let obj = try? JSONSerialization.jsonObject(with: Data(String(c[a...b]).utf8)) as? [String: Any]
        else { return nil }
        if let arr = obj["acoes"] as? [[String: Any]] {
            return arr.map { ($0["acao"] as? String ?? "?").lowercased() }
        }
        if let ac = obj["acao"] as? String { return [ac.lowercased()] }
        return []   // JSON válido mas sem ação (conversa)
    }

    static func run() {
        let casos: [Caso] = [
            Caso(comando: "abre o safari", esperado: ["abrir_app"]),
            Caso(comando: "coloca o volume em 40", esperado: ["volume"]),
            Caso(comando: "tira um print", esperado: ["screenshot"]),
            Caso(comando: "que horas são", esperado: ["shell"]),
            Caso(comando: "abre whatsapp e telegram", esperado: ["abrir_varios", "abrir_app"]),
            Caso(comando: "abre o safari, coloca o volume em 50 e tira um print",
                 esperado: ["abrir_app", "volume", "screenshot"]),
            Caso(comando: "me conta uma piada", esperado: ["nenhuma"]),
        ]

        Task { @MainActor in
            print("╔══════════════════════════════════════════════════════════╗")
            print("║   TESTE LLM AO VIVO — OllamaService + AgentRouter (parse)  ║")
            print("╚══════════════════════════════════════════════════════════╝")

            let ollama = OllamaService()
            print("\n[1] Health-check (checkConnection)…")
            await ollama.checkConnection()
            guard ollama.isConnected else {
                print("  ❌ Ollama OFFLINE — suba com `ollama serve` e tente de novo.")
                exit(1)
            }
            print("  ✅ Conectado. Modelo selecionado: \(ollama.selectedModel)")
            print("  Modelos disponíveis: \(ollama.availableModels.joined(separator: ", "))")

            var ok = 0, jsonOk = 0
            for c in casos {
                let hist = [ChatMessage(role: "user", content: c.comando)]
                let t0 = Date()
                let raw = (try? await ollama.chat(history: hist)) ?? ""
                let dt = Date().timeIntervalSince(t0)
                let parsed = acoes(de: raw)
                let jsonValido = parsed != nil
                if jsonValido { jsonOk += 1 }
                // Passa se QUALQUER ação esperada aparecer (tolera variação legítima do modelo)
                let got = parsed ?? []
                let acertou = c.esperado.contains { got.contains($0) } ||
                              (c.esperado == ["nenhuma"] && (got.isEmpty || got == ["nenhuma"]))
                if acertou { ok += 1 }
                let mark = acertou ? "✅" : (jsonValido ? "⚠️ " : "❌")
                print(String(format: "\n%@ \"%@\"  (%.2fs)", mark, c.comando, dt))
                print("   esperado: \(c.esperado)  |  obtido: \(got)")
                if !jsonValido { print("   raw: \(raw.prefix(120))") }
            }

            print("\n──────────────────────────────────────────")
            print("JSON válido: \(jsonOk)/\(casos.count)   |   Ação esperada: \(ok)/\(casos.count)")
            print("[TESTLLM] concluído")
            exit(ok == casos.count && jsonOk == casos.count ? 0 : 2)
        }
        RunLoop.main.run()
    }
}
