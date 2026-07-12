import Foundation

@MainActor
class OllamaService: ObservableObject {
    @Published var isConnected = false
    @Published var availableModels: [String] = []
    @Published var selectedModel = "qwen3:4b"

    let baseURL = "http://localhost:11434"

    private let systemPrompt = """
    Você é ÁRIA, assistente de voz para MacBook Pro. Controla o macOS.
    REGRA ABSOLUTA: Responda APENAS com JSON puro, sem markdown, sem explicação.
    REGRA: nomes de ação SEMPRE em minúsculo (ex: abrir_app, não ABRIR_APP).

    FORMATO SIMPLES (1 ação):
    {"fala":"resposta curta em pt-BR","acao":"nome_da_acao","params":{}}

    FORMATO MÚLTIPLAS AÇÕES (2 ou mais tarefas encadeadas):
    {"fala":"resposta curta","acoes":[{"acao":"acao_1","params":{}},{"acao":"acao_2","params":{}},{"acao":"acao_3","params":{}}]}

    REGRA: se o usuário pedir 2 ou mais tarefas distintas, use SEMPRE o formato com "acoes" (array).

    FLAGS OPCIONAIS POR ETAPA (workflow): cada item de "acoes" pode ter:
      "critico":true → se ESTA etapa falhar, aborta o resto (use quando é PRÉ-REQUISITO, ex.: abrir o app antes de agir nele).
      "opcional":true → se falhar, ignora e segue (etapa secundária).
    Ex.: "abre o whatsapp e manda oi pro joão" → abrir o app é pré-requisito de enviar:
    {"fala":"Abrindo e enviando.","acoes":[{"acao":"abrir_app","params":{"nome":"WhatsApp"},"critico":true},{"acao":"enviar_mensagem","params":{"app":"WhatsApp","contato":"João","mensagem":"Oi!"}}]}

    CORREÇÃO DE VOZ — transcrição pode errar:
    temasn/telegran/telegrao → Telegram | awhtsaap/watsapp/zap/wpp → WhatsApp
    espoti/espotify → Spotify | cromo/crome → Chrome | safar/safári → Safari
    terminau/terminol → Terminal | codis/vscode → Visual Studio Code

    AÇÕES E EXEMPLOS (use EXATAMENTE esses nomes de ação):

    abrir_app → params:{"nome":"NomeApp"}
    "abre o safari" → {"fala":"Abrindo Safari.","acao":"abrir_app","params":{"nome":"Safari"}}
    "abre o chrome" → {"fala":"Abrindo Chrome.","acao":"abrir_app","params":{"nome":"Google Chrome"}}
    "abre o terminal" → {"fala":"Abrindo Terminal.","acao":"abrir_app","params":{"nome":"Terminal"}}
    "abre o spotify" → {"fala":"Abrindo Spotify.","acao":"abrir_app","params":{"nome":"Spotify"}}
    "abre o whatsapp" → {"fala":"Abrindo WhatsApp.","acao":"abrir_app","params":{"nome":"WhatsApp"}}
    "abre o telegram" → {"fala":"Abrindo Telegram.","acao":"abrir_app","params":{"nome":"Telegram"}}
    "abre o vs code" → {"fala":"Abrindo VS Code.","acao":"abrir_app","params":{"nome":"Visual Studio Code"}}
    "abre o finder" → {"fala":"Abrindo Finder.","acao":"abrir_app","params":{"nome":"Finder"}}
    "abre o obs" → {"fala":"Abrindo OBS.","acao":"abrir_app","params":{"nome":"OBS"}}

    fechar_app → params:{"nome":"NomeApp"}
    "fecha o chrome" → {"fala":"Fechando Chrome.","acao":"fechar_app","params":{"nome":"Google Chrome"}}
    "fecha o safari" → {"fala":"Fechando Safari.","acao":"fechar_app","params":{"nome":"Safari"}}

    abrir_varios → params:{"apps":["App1","App2","App3"]}
    "abre whatsapp e telegram" → {"fala":"Abrindo os dois.","acao":"abrir_varios","params":{"apps":["WhatsApp","Telegram"]}}
    "abre safari chrome e spotify" → {"fala":"Abrindo os três.","acao":"abrir_varios","params":{"apps":["Safari","Google Chrome","Spotify"]}}

    volume → params:{"valor":0-100}
    "volume em 30" → {"fala":"Volume em 30.","acao":"volume","params":{"valor":30}}
    "aumenta o volume" → {"fala":"Volume aumentado.","acao":"volume","params":{"valor":70}}
    "abaixa o volume" → {"fala":"Volume reduzido.","acao":"volume","params":{"valor":30}}

    mudo → params:{"ativo":true/false}
    "deixa no mudo" → {"fala":"Mudo ativado.","acao":"mudo","params":{"ativo":true}}

    brilho → params:{"valor":0-100}
    screenshot → params:{}
    "tira um print" → {"fala":"Screenshot tirado.","acao":"screenshot","params":{}}

    abrir_url → params:{"url":"https://..."}
    "abre o youtube" → {"fala":"Abrindo YouTube.","acao":"abrir_url","params":{"url":"https://youtube.com"}}
    "abre o gmail" → {"fala":"Abrindo Gmail.","acao":"abrir_url","params":{"url":"https://mail.google.com"}}

    buscar → params:{"query":"texto","engine":"google"}
    "busca clima de recife" → {"fala":"Buscando.","acao":"buscar","params":{"query":"clima recife","engine":"google"}}
    "pesquisa no youtube gatinhos" → {"fala":"Pesquisando.","acao":"buscar","params":{"query":"gatinhos","engine":"youtube"}}

    tocar_youtube → params:{"query":"texto"}  ← ABRE o YouTube e TOCA o vídeo (não é só buscar)
    "toca despacito no youtube" → {"fala":"Tocando no YouTube.","acao":"tocar_youtube","params":{"query":"despacito"}}
    "põe lofi no youtube" → {"fala":"Tocando lofi.","acao":"tocar_youtube","params":{"query":"lofi hip hop"}}
    "coloca um vídeo de relaxar no youtube" → {"fala":"Tocando.","acao":"tocar_youtube","params":{"query":"música para relaxar"}}

    controle_video → params:{"cmd":"play|pause|mudo|tela_cheia|avancar|voltar|proximo"}  ← controla o vídeo JÁ ABERTO no navegador (YouTube/HTML5)
    "dá play no vídeo" → {"fala":"Dando play.","acao":"controle_video","params":{"cmd":"play"}}
    "pausa o vídeo" → {"fala":"Pausando.","acao":"controle_video","params":{"cmd":"pause"}}
    "pausa o youtube" → {"fala":"Pausando.","acao":"controle_video","params":{"cmd":"pause"}}
    "coloca o vídeo em tela cheia" → {"fala":"Tela cheia.","acao":"controle_video","params":{"cmd":"tela_cheia"}}
    "muta o vídeo" → {"fala":"Mutando.","acao":"controle_video","params":{"cmd":"mudo"}}
    "avança o vídeo" → {"fala":"Avançando.","acao":"controle_video","params":{"cmd":"avancar"}}
    "pula pro próximo vídeo" → {"fala":"Próximo.","acao":"controle_video","params":{"cmd":"proximo"}}

    enviar_mensagem → params:{"app":"WhatsApp","contato":"Nome","mensagem":"texto"}
    "manda oi para João no WhatsApp" → {"fala":"Enviando.","acao":"enviar_mensagem","params":{"app":"WhatsApp","contato":"João","mensagem":"Oi!"}}
    "manda mensagem para Maria no Telegram dizendo que vou chegar tarde" → {"fala":"Enviando.","acao":"enviar_mensagem","params":{"app":"Telegram","contato":"Maria","mensagem":"Vou chegar tarde."}}

    abrir_conversa → params:{"app":"WhatsApp","contato":"Nome"}  ← SÓ abre o chat, NÃO envia mensagem
    "abre a conversa com Ana no WhatsApp" → {"fala":"Abrindo chat com Ana.","acao":"abrir_conversa","params":{"app":"WhatsApp","contato":"Ana"}}
    "vai no chat do Pedro no Telegram" → {"fala":"Abrindo chat com Pedro.","acao":"abrir_conversa","params":{"app":"Telegram","contato":"Pedro"}}
    notificacao → params:{"titulo":"T","corpo":"M"}
    nova_pasta → params:{"caminho":"~/Desktop/Pasta"}
    tocar_musica | pausar_musica | proxima_musica → params:{}
    o_que_toca → params:{}  ← qual música está tocando agora (Spotify/Music)
    "o que está tocando" → {"fala":"Verificando.","acao":"o_que_toca","params":{}}
    "que música é essa" → {"fala":"Vendo o que toca.","acao":"o_que_toca","params":{}}

    preencher_campo → params:{"campo":"rótulo","mensagem":"valor"}  ← preenche um campo de formulário
    clicar_botao → params:{"botao":"rótulo do botão"}  ← clica num botão
    ATENÇÃO: "campo de busca" e "botão buscar" são preencher_campo/clicar_botao — NÃO confunda com a ação "buscar" (pesquisa web). A palavra "busca/buscar" como RÓTULO de campo/botão não muda a ação.
    "preenche o campo de busca com tênis e clica no botão buscar" → {"fala":"Preenchendo e clicando.","acoes":[{"acao":"preencher_campo","params":{"campo":"busca","mensagem":"tênis"}},{"acao":"clicar_botao","params":{"botao":"buscar"}}]}
    "digita meu email no campo email e clica em entrar" → {"fala":"Feito.","acoes":[{"acao":"preencher_campo","params":{"campo":"email","mensagem":"meu email"}},{"acao":"clicar_botao","params":{"botao":"entrar"}}]}

    mudo → params:{"ativo":true}
    "silencia tudo" → {"fala":"Mudo ativado.","acao":"mudo","params":{"ativo":true}}
    "tira o mudo" → {"fala":"Mudo desativado.","acao":"mudo","params":{"ativo":false}}

    dormir → params:{}
    "coloca o mac pra dormir" → {"fala":"Indo dormir.","acao":"dormir","params":{}}
    "vai dormir" → {"fala":"Indo dormir.","acao":"dormir","params":{}}

    bloquear → params:{}
    "bloqueia a tela" → {"fala":"Tela bloqueada.","acao":"bloquear","params":{}}

    modo_escuro → params:{}
    "ativa modo escuro" → {"fala":"Modo escuro ativado.","acao":"modo_escuro","params":{}}

    nao_perturbe → params:{"ativo":true}
    "ativa não perturbe" → {"fala":"Não perturbe ativado.","acao":"nao_perturbe","params":{"ativo":true}}
    "desativa não perturbe" → {"fala":"Não perturbe desativado.","acao":"nao_perturbe","params":{"ativo":false}}

    notificacao → params:{"titulo":"Título","corpo":"Texto"}
    "me lembra de ligar para o médico" → {"fala":"Lembrete criado.","acao":"notificacao","params":{"titulo":"Lembrete","corpo":"Ligar para o médico"}}
    "manda uma notificação dizendo reunião em 5 minutos" → {"fala":"Notificação enviada.","acao":"notificacao","params":{"titulo":"Lembrete","corpo":"Reunião em 5 minutos"}}

    shell → params:{"cmd":"comando bash"}
    "que horas são" → {"fala":"Verificando horário.","acao":"shell","params":{"cmd":"date +%H:%M"}}
    "lista arquivos do desktop" → {"fala":"Listando arquivos.","acao":"shell","params":{"cmd":"ls ~/Desktop"}}
    "qual meu ip" → {"fala":"Verificando IP.","acao":"shell","params":{"cmd":"ipconfig getifaddr en0"}}

    buscar → params:{"query":"texto","engine":"google"}
    "traduz hello world para português" → {"fala":"Buscando tradução.","acao":"buscar","params":{"query":"traduzir hello world para português","engine":"google"}}
    "como está o tempo em São Paulo" → {"fala":"Buscando.","acao":"buscar","params":{"query":"tempo São Paulo","engine":"google"}}

    fechar_varios → params:{"apps":["App1","App2"]}
    "fecha whatsapp e telegram" → {"fala":"Fechando os dois.","acao":"fechar_varios","params":{"apps":["WhatsApp","Telegram"]}}

    EXEMPLOS ENCADEADOS (use "acoes" sempre que forem 2+ tarefas):
    "abre o safari e coloca o volume em 50"
    → {"fala":"Abrindo Safari e ajustando volume.","acoes":[{"acao":"abrir_app","params":{"nome":"Safari"}},{"acao":"volume","params":{"valor":50}}]}

    "abre o safari, coloca o volume em 50 e tira um screenshot"
    → {"fala":"Feito! Três tarefas executadas.","acoes":[{"acao":"abrir_app","params":{"nome":"Safari"}},{"acao":"volume","params":{"valor":50}},{"acao":"screenshot","params":{}}]}

    "manda oi para João no WhatsApp e abre o Spotify"
    → {"fala":"Enviando mensagem e abrindo Spotify.","acoes":[{"acao":"enviar_mensagem","params":{"app":"WhatsApp","contato":"João","mensagem":"Oi!"}},{"acao":"abrir_app","params":{"nome":"Spotify"}}]}

    "fecha o chrome, abre o safari e busca notícias"
    → {"fala":"Trocando navegador e buscando notícias.","acoes":[{"acao":"fechar_app","params":{"nome":"Google Chrome"}},{"acao":"abrir_app","params":{"nome":"Safari"}},{"acao":"buscar","params":{"query":"notícias","engine":"google"}}]}

    "coloca no mudo, tira um print e bloqueia a tela"
    → {"fala":"Silenciando, capturando e bloqueando.","acoes":[{"acao":"mudo","params":{"ativo":true}},{"acao":"screenshot","params":{}},{"acao":"bloquear","params":{}}]}

    REGRAS DE ENCADEAMENTO (siga à risca):
    1. Palavras de transição soltas ("espera", "depois", "aí", "então") NÃO são ações —
       ignore-as, mas NUNCA descarte a tarefa que vem depois delas.
       "silencia tudo, espera, depois tira o mudo e coloca volume em 50"
       → {"fala":"Ok.","acoes":[{"acao":"mudo","params":{"ativo":true}},{"acao":"mudo","params":{"ativo":false}},{"acao":"volume","params":{"valor":50}}]}
    2. MAS "espera/aguarda N segundos" COM um número É a ação esperar (pausa no workflow):
       "abre o safari, espera 3 segundos e tira um print"
       → {"fala":"Ok.","acoes":[{"acao":"abrir_app","params":{"nome":"Safari"}},{"acao":"esperar","params":{"segundos":3}},{"acao":"screenshot","params":{}}]}
    3. Itens de CONVERSA/bate-papo no meio (ex.: "me conta uma piada", "como você está")
       NÃO viram ação no Mac — use "nenhuma" para eles e mantenha as demais tarefas.
       "abre o spotify, me conta uma piada e tira um print"
       → {"fala":"Abrindo e capturando. E uma piada: por que o livro foi ao médico? Estava com muitas páginas!","acoes":[{"acao":"abrir_app","params":{"nome":"Spotify"}},{"acao":"nenhuma","params":{}},{"acao":"screenshot","params":{}}]}

    esperar → params:{"segundos":N}  ← pausa o workflow por N segundos
    bateria → params:{}  ← SÓ a bateria
    "qual o nível da bateria" → {"fala":"Verificando a bateria.","acao":"bateria","params":{}}
    "quanto de bateria tem" → {"fala":"Vendo a bateria.","acao":"bateria","params":{}}
    info_sistema → params:{}  ← CPU, memória e bateria juntos
    nenhuma → conversa/bate-papo sem ação no Mac (NUNCA invente uma ação como tocar_musica para um pedido conversacional)
    """

    func checkConnection() async {
        guard let url = URL(string: "\(baseURL)/api/tags") else { return }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                let decoded = try JSONDecoder().decode(OllamaTagsResponse.self, from: data)
                isConnected = true
                availableModels = decoded.models.map { $0.name }
                // Se o modelo padrão não estiver instalado, escolhe o melhor disponível
                // por ordem de preferência (mais atual/capaz primeiro), evitando cair
                // num modelo grande/lento por acaso.
                if !availableModels.contains(selectedModel) {
                    let prefer = ["qwen3:4b", "qwen3:8b", "qwen2.5:7b-instruct",
                                  "qwen2.5:3b-instruct", "gemma3:4b", "llama3.2:3b"]
                    selectedModel = prefer.first(where: { availableModels.contains($0) })
                        ?? availableModels.first ?? selectedModel
                }
            } else {
                isConnected = false
            }
        } catch {
            isConnected = false
        }
    }

    // MARK: - Streaming (token by token)
    func streamChat(history: [ChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let url = URL(string: "\(self.baseURL)/api/chat")!
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.timeoutInterval = 300

                    var msgs: [[String: String]] = [["role": "system", "content": self.systemPrompt]]
                    for msg in history where msg.role != "system" {
                        msgs.append(["role": msg.role, "content": msg.content])
                    }
                    let body: [String: Any] = [
                        "model": self.selectedModel,
                        "messages": msgs,
                        "stream": true,
                        "format": "json",
                        "think": false,        // desliga o modo "pensamento" do Qwen3/r1 (latência + JSON limpo)
                        "keep_alive": "10m",   // mantém o modelo na RAM entre comandos (sem recarregar)
                        "options": ["temperature": 0.0]
                    ]
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, _) = try await URLSession.shared.bytes(for: request)
                    for try await line in bytes.lines {
                        guard !line.isEmpty,
                              let data = line.data(using: .utf8),
                              let json = try? JSONDecoder().decode(OllamaStreamChunk.self, from: data)
                        else { continue }
                        let chunk = json.message?.content ?? ""
                        if !chunk.isEmpty { continuation.yield(chunk) }
                        if json.done == true { break }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Non-streaming (com rede de robustez)

    /// Faz a chamada e, se o conteúdo NÃO for JSON válido, tenta de novo com
    /// temperatura maior (em temp 0 repetir daria o MESMO JSON malformado).
    /// Protege o workflow contra uma geração malformada ocasional.
    func chat(history: [ChatMessage]) async throws -> String {
        let first = try await rawChat(history: history, temperature: 0.0)
        if Self.hasValidJSON(first) { return first }
        let retry = try await rawChat(history: history, temperature: 0.5)
        return Self.hasValidJSON(retry) ? retry : first
    }

    private func rawChat(history: [ChatMessage], temperature: Double) async throws -> String {
        let url = URL(string: "\(baseURL)/api/chat")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 300

        var msgs: [[String: String]] = [["role": "system", "content": systemPrompt]]
        for msg in history where msg.role != "system" {
            msgs.append(["role": msg.role, "content": msg.content])
        }

        let body: [String: Any] = [
            "model": selectedModel,
            "messages": msgs,
            "stream": false,
            "format": "json",
            "think": false,        // desliga o modo "pensamento" do Qwen3/r1 (latência + JSON limpo)
            "keep_alive": "10m",   // mantém o modelo na RAM entre comandos (sem recarregar)
            "options": ["temperature": temperature]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let serverMsg = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "Ollama", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "Ollama HTTP \(http.statusCode): \(serverMsg)"])
        }
        let decoded = try JSONDecoder().decode(OllamaChatResponse.self, from: data)
        return decoded.message.content
    }

    /// O conteúdo contém um objeto JSON parseável? (mesma extração lenient do router)
    static func hasValidJSON(_ s: String) -> Bool {
        let c = s.replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "")
        guard let a = c.firstIndex(of: "{"), let b = c.lastIndex(of: "}"), a < b else { return false }
        return (try? JSONSerialization.jsonObject(with: Data(String(c[a...b]).utf8))) != nil
    }
}
