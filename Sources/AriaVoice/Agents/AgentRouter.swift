import Foundation

/// Roteador central: recebe JSON do LLM e despacha para o agente correto
@MainActor
class AgentRouter: ObservableObject {
    @Published var lastAction  = ""
    @Published var lastResult  = ""
    @Published var debugLog: [String] = []

    // Os agentes são criados localmente dentro de route(), que roda FORA da main thread
    // (via runOffMain) para não congelar a UI/áudio com shell()/osascript() síncronos.

    /// Processa a resposta raw do LLM — suporta ação única e array de ações
    func process(_ rawLLM: String) async -> String {
        log("📥 LLM raw: \(rawLLM.prefix(300))")

        guard let json = extractJSON(from: rawLLM) else {
            log("⚠️ Sem JSON — retornando texto literal")
            return rawLLM
        }

        let fala = json["fala"] as? String ?? json["resposta"] as? String ?? rawLLM

        // ── Modo multi-ação ────────────────────────────────────────────────
        if let acoes = json["acoes"] as? [[String: Any]], !acoes.isEmpty {
            log("🔗 Multi-ação: \(acoes.count) tarefas")
            var results: [String] = []
            var failures: [String] = []
            for (i, step) in acoes.enumerated() {
                let acao     = step["acao"]   as? String ?? "nenhuma"
                let params   = step["params"] as? [String: Any] ?? [:]
                let critico  = (step["critico"]  as? Bool) ?? (step["critical"] as? Bool) ?? false
                let opcional = (step["opcional"] as? Bool) ?? (step["optional"] as? Bool) ?? false
                log("  [\(i+1)/\(acoes.count)] \(acao)\(critico ? " (crítico)" : "")")
                // Respiro curto entre etapas. Ações que mudam estado (abrir app, tocar
                // vídeo, enviar msg) JÁ esperam prontidão internamente (verify-and-wait),
                // então 0.15s basta; ações instantâneas não pagam o antigo 0.4s. Não bloqueia a UI.
                if i > 0 { try? await Task.sleep(nanoseconds: 150_000_000) }
                let r = await runOffMain(acao: acao.lowercased(), params: params)
                results.append(r)
                let failed = (r.hasPrefix("⚠️") || r.hasPrefix("⛔")) && !opcional
                if failed { failures.append("\(i+1) \(acao)") }
                // Feedback AO VIVO por etapa na UI
                lastAction = "[\(i+1)/\(acoes.count)] \(acao)"
                lastResult = failed ? r : "✅ \(i+1)/\(acoes.count) \(acao)"
                // Etapa CRÍTICA (pré-requisito) falhou → aborta o restante do workflow
                if failed && critico {
                    let restantes = acoes.count - (i + 1)
                    log("⛔ Etapa crítica \(i+1) falhou — abortando \(restantes) etapa(s)")
                    lastAction = "parou na etapa \(i+1)/\(acoes.count)"
                    lastResult = "⛔ Parou: etapa \(i+1) (\(acao)) era pré-requisito e falhou."
                    return "Parei no passo \(i+1): \(acao) falhou e era necessário para o resto."
                }
            }
            let summary = results.joined(separator: " | ")
            log("✅ Multi resultado: \(summary)")

            // Resultado AGREGADO das N etapas (não só a última) — o usuário precisa
            // saber QUANTAS e QUAIS falharam ao comandar várias tarefas por voz.
            let okCount = acoes.count - failures.count
            lastAction = "\(acoes.count) tarefas"
            lastResult = failures.isEmpty
                ? "✅ \(okCount)/\(acoes.count) tarefas concluídas"
                : "⚠️ \(okCount)/\(acoes.count) ok — falhou: \(failures.joined(separator: ", "))"

            // Reconcilia a fala (prevista pelo LLM ANTES da execução) com o resultado real
            let anySuccess = results.contains {
                !$0.hasPrefix("⚠️") && !$0.hasPrefix("⛔") && $0 != "💬 Conversa"
            }
            if !anySuccess {
                return "Não consegui executar nenhuma das ações pedidas."
            }
            if !failures.isEmpty {
                return "\(fala) Mas \(failures.count) de \(acoes.count) tarefas falharam."
            }
            return fala
        }

        // ── Modo ação única (compatibilidade) ──────────────────────────────
        let acao   = json["acao"]   as? String ?? json["comando"] as? String ?? "nenhuma"
        let params = json["params"] as? [String: Any] ?? json["parametros"] as? [String: Any] ?? [:]

        log("🎯 Ação: \(acao) | Params: \(params)")
        lastAction = acao

        let result = await runOffMain(acao: acao.lowercased(), params: params)
        lastResult = result
        log("✅ Resultado: \(result)")

        return fala
    }

    /// Executa a ação FORA da main thread. shell()/osascript() dos agentes são síncronos
    /// (Process.waitUntilExit) e bloqueariam a UI, o medidor de áudio e o TTS. route é
    /// nonisolated e cria seus próprios agentes (não toca @Published), portanto é seguro
    /// rodar fora do MainActor.
    private func runOffMain(acao: String, params: [String: Any]) async -> String {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: self.route(acao: acao, params: params))
            }
        }
    }

    nonisolated private func route(acao: String, params: [String: Any]) -> String {
        let appAgent       = AppAgent()
        let systemAgent    = SystemAgent()
        let webAgent       = WebAgent()
        let mediaAgent     = MediaAgent()
        let shellAgent     = ShellAgent()
        let messagingAgent = MessagingAgent()

        let nome      = (params["nome"]      as? String ?? params["app"]     as? String ?? "").trimmingCharacters(in: .whitespaces)
        let contato   = (params["contato"]   as? String ?? params["para"]    as? String ?? params["destinatario"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        let mensagem  = (params["mensagem"]  as? String ?? params["texto"]   as? String ?? params["msg"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        let appMsg    = (params["app"]       as? String ?? nome)
        let url   = (params["url"]   as? String ?? "").trimmingCharacters(in: .whitespaces)
        let query = (params["query"] as? String ?? params["busca"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        let cmd   = (params["cmd"]   as? String ?? "").trimmingCharacters(in: .whitespaces)
        let valor = (params["valor"] as? Int)
            ?? (params["valor"] as? Double).map(Int.init)
            ?? (params["valor"] as? String).flatMap { Int($0) }
            ?? -1
        let ativo = params["ativo"] as? Bool ?? true
        let titulo = params["titulo"] as? String ?? "ÁRIA"
        let corpo  = params["corpo"]  as? String ?? params["mensagem"] as? String ?? ""
        let caminho = params["caminho"] as? String ?? ""

        switch acao {

        // ── App control ───────────────────────────────
        case "abrir_app", "open_app", "abre", "abrir":
            return appAgent.open(nome.isEmpty ? query : nome)

        case "abrir_varios", "open_several", "open_apps":
            let apps = params["apps"] as? [String] ?? []
            if apps.isEmpty { return appAgent.open(nome) }
            // Pausa entre aberturas para evitar corrida de ativação/foco (roda off-main)
            var results: [String] = []
            for (i, app) in apps.enumerated() {
                if i > 0 { Thread.sleep(forTimeInterval: 0.3) }
                results.append(appAgent.open(app))
            }
            return results.joined(separator: " | ")

        case "fechar_app", "close_app", "fechar":
            return appAgent.close(nome)

        case "fechar_varios", "close_several":
            let apps = params["apps"] as? [String] ?? []
            if apps.isEmpty { return appAgent.close(nome) }
            return apps.map { appAgent.close($0) }.joined(separator: " | ")

        // ── System ────────────────────────────────────
        case "volume":
            return valor >= 0 ? systemAgent.setVolume(valor) : "⚠️ Valor inválido"

        case "mudo", "mute":
            return systemAgent.mute(ativo)

        case "brilho", "brightness":
            return valor >= 0 ? systemAgent.setBrightness(valor) : "⚠️ Valor inválido"

        case "screenshot", "print", "captura":
            return systemAgent.screenshot()

        case "notificacao", "notification", "notificar":
            return systemAgent.notify(title: titulo, body: corpo)

        case "modo_escuro", "dark_mode":
            return systemAgent.toggleDarkMode()

        case "nao_perturbe", "do_not_disturb":
            return systemAgent.setDoNotDisturb(ativo)

        case "bloquear", "lock":
            return systemAgent.lockScreen()

        case "dormir", "sleep":
            return systemAgent.sleep()

        case "bateria", "battery", "info_bateria":
            return systemAgent.batteryInfo()

        case "info_sistema", "system_info":
            return systemAgent.systemInfo()

        // ── Mensagens ─────────────────────────────────
        case "enviar_mensagem", "send_message", "mensagem", "mandar_mensagem", "mandar":
            return messagingAgent.send(app: appMsg, contact: contato, message: mensagem)

        case "abrir_conversa", "open_chat", "abrir_chat":
            return messagingAgent.openChat(app: appMsg, contact: contato)

        case "clicar_botao", "click_button", "clicar":
            let botao = params["botao"] as? String ?? params["button"] as? String ?? nome
            return messagingAgent.clickButton(appName: appMsg.isEmpty ? nome : appMsg, buttonTitle: botao)

        case "preencher_campo", "fill_field", "digitar":
            let campo = params["campo"] as? String ?? params["field"] as? String ?? ""
            return messagingAgent.fillField(appName: appMsg.isEmpty ? nome : appMsg, placeholder: campo, value: mensagem)

        // ── Web ───────────────────────────────────────
        case "abrir_url", "open_url", "url":
            let target = url.isEmpty ? nome : url
            // Se parece URL ou site conhecido — abre no browser
            let knownSites = ["github", "youtube", "google", "twitter", "instagram", "linkedin",
                              "reddit", "netflix", "amazon", "gmail", "drive", "notion", "figma"]
            let isKnownSite = knownSites.contains { target.lowercased().contains($0) }
            if target.lowercased().hasPrefix("http") || target.contains(".com") ||
               target.contains(".org") || isKnownSite {
                return webAgent.openURL(target)
            }
            // Senão tenta como nome de app
            return appAgent.open(target)

        case "buscar", "buscar_web", "search", "pesquisar":
            let engine = (params["engine"] as? String ?? params["motor"] as? String ?? "google").trimmingCharacters(in: .whitespaces)
            return webAgent.search(query.isEmpty ? nome : query, engine: engine.isEmpty ? "google" : engine)

        // ── Media ─────────────────────────────────────
        case "tocar_musica", "play", "tocar":
            return mediaAgent.play()

        case "pausar_musica", "pause", "pausar":
            return mediaAgent.pause()

        case "proxima_musica", "next", "proxima":
            return mediaAgent.next()

        case "musica_anterior", "previous", "anterior":
            return mediaAgent.previous()

        case "o_que_toca", "now_playing":
            return mediaAgent.nowPlaying()

        // ── Vídeo no navegador (YouTube / HTML5) ──────
        case "tocar_youtube", "youtube", "play_youtube", "tocar_video":
            return webAgent.playYouTube(query.isEmpty ? nome : query)

        case "controle_video", "video", "controlar_video", "video_control":
            // cmd: play|pause|mudo|tela_cheia|avancar|voltar|proximo
            let vc = cmd.isEmpty ? (params["acao_video"] as? String ?? "play") : cmd
            return mediaAgent.controlVideo(vc)

        // ── Shell / File ──────────────────────────────
        case "shell", "comando", "terminal":
            return shellAgent.run(cmd)

        case "nova_pasta", "criar_pasta", "mkdir", "novo_diretorio", "new_folder", "criar_diretorio":
            return shellAgent.createFolder(caminho.isEmpty ? nome : caminho)

        case "esperar", "aguardar", "wait", "pausa":
            let seg = (params["segundos"] as? Int)
                ?? (params["segundos"] as? Double).map(Int.init)
                ?? (params["segundos"] as? String).flatMap { Int($0) }
                ?? (params["valor"] as? Int) ?? 1
            let s = max(0, min(15, seg))
            Thread.sleep(forTimeInterval: Double(s))   // roda off-main em route()
            return "✅ Esperei \(s)s"

        case "nenhuma", "none", "":
            return "💬 Conversa"

        default:
            // Só abre como app se a palavra realmente corresponder a um app instalado/conhecido.
            // Caso contrário (ação alucinada pelo LLM), retorna "Ação desconhecida" sem efeito colateral.
            let candidato = nome.isEmpty ? acao : nome
            if !candidato.isEmpty && !candidato.contains("_") && candidato.count > 2
               && appAgent.isKnownApp(candidato) {
                return appAgent.open(candidato)
            }
            return "⚠️ Ação desconhecida: \(acao)"
        }
    }

    // MARK: - JSON Extraction

    private func extractJSON(from text: String) -> [String: Any]? {
        var clean = text
        clean = clean.replacingOccurrences(of: "```json", with: "")
        clean = clean.replacingOccurrences(of: "```", with: "")
        clean = clean.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let start = clean.firstIndex(of: "{"),
              let end   = clean.lastIndex(of: "}") else { return nil }
        let jsonStr = String(clean[start...end])

        // Tentativa 1: JSON direto
        if let data = jsonStr.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return json
        }

        // Tentativa 2: reparar erros comuns do LLM
        let repaired = repairJSON(jsonStr)
        if let data = repaired.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            log("🔧 JSON reparado")
            return json
        }

        log("⚠️ JSON inválido: \(jsonStr.prefix(100))")
        return nil
    }

    /// Repara erros comuns de JSON gerado por LLMs
    private func repairJSON(_ s: String) -> String {
        var r = s
        // Corrige chaves sem aspas: {caminho:"val"} → {"caminho":"val"}
        let unquotedKey = try? NSRegularExpression(pattern: #"(\{|,)\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*:"#)
        if let rx = unquotedKey {
            r = rx.stringByReplacingMatches(in: r, range: NSRange(r.startIndex..., in: r),
                                            withTemplate: #"$1"$2":"#)
        }
        // Corrige True/False → true/false
        r = r.replacingOccurrences(of: ": True",  with: ": true")
        r = r.replacingOccurrences(of: ": False", with: ": false")
        r = r.replacingOccurrences(of: ":True",   with: ":true")
        r = r.replacingOccurrences(of: ":False",  with: ":false")
        // Remove trailing comma antes de }
        let trailingComma = try? NSRegularExpression(pattern: #",\s*\}"#)
        if let rx = trailingComma {
            r = rx.stringByReplacingMatches(in: r, range: NSRange(r.startIndex..., in: r),
                                            withTemplate: "}")
        }
        return r
    }

    private func log(_ msg: String) {
        debugLog.append(msg)
        if debugLog.count > 50 { debugLog.removeFirst() }
        print("[AgentRouter] \(msg)")
    }
}
