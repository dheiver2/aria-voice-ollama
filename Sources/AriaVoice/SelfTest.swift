import Foundation

/// Harness de teste do motor de execução sequencial (AgentRouter).
/// Rodar com: AriaVoice --selftest   (NÃO instancia VoiceManager/UI — sem TCC de microfone)
/// Usa ações seguras/observáveis para validar encadeamento, ordem, continuidade
/// após erro, timing do delay não-bloqueante e o caminho off-main.
enum SelfTest {

    struct Caso { let nome: String; let espera: Int; let json: String }

    static func run() {
        // 10 shells em ordem para o caso longo
        let dez = (1...10).map { "{\"acao\":\"shell\",\"params\":{\"cmd\":\"echo p\($0)\"}}" }
            .joined(separator: ",")

        let casos: [Caso] = [
            Caso(nome: "5 ações em ordem", espera: 5, json: """
            {"fala":"ok","acoes":[
              {"acao":"shell","params":{"cmd":"echo P1"}},
              {"acao":"shell","params":{"cmd":"echo P2"}},
              {"acao":"info_sistema","params":{}},
              {"acao":"bateria","params":{}},
              {"acao":"shell","params":{"cmd":"echo P5"}}
            ]}
            """),
            Caso(nome: "erro no meio NÃO aborta a cadeia", espera: 3, json: """
            {"fala":"ok","acoes":[
              {"acao":"shell","params":{"cmd":"echo ANTES"}},
              {"acao":"abrir_app","params":{"nome":"AppInexistente_zzz_999"}},
              {"acao":"shell","params":{"cmd":"echo DEPOIS"}}
            ]}
            """),
            Caso(nome: "10 ações seguras", espera: 10, json: "{\"fala\":\"ok\",\"acoes\":[\(dez)]}"),
            Caso(nome: "etapa CRÍTICA falha → aborta o resto", espera: 1, json: """
            {"fala":"ok","acoes":[
              {"acao":"abrir_app","params":{"nome":"AppInexistente_zzz_999"},"critico":true},
              {"acao":"shell","params":{"cmd":"echo NAO_DEVE_RODAR"}}
            ]}
            """),
            Caso(nome: "etapa OPCIONAL falha → segue normal", espera: 3, json: """
            {"fala":"ok","acoes":[
              {"acao":"shell","params":{"cmd":"echo A"}},
              {"acao":"abrir_app","params":{"nome":"AppInexistente_zzz_999"},"opcional":true},
              {"acao":"shell","params":{"cmd":"echo B"}}
            ]}
            """),
            Caso(nome: "esperar 1s entre passos", espera: 3, json: """
            {"fala":"ok","acoes":[
              {"acao":"shell","params":{"cmd":"echo X"}},
              {"acao":"esperar","params":{"segundos":1}},
              {"acao":"shell","params":{"cmd":"echo Y"}}
            ]}
            """),
            Caso(nome: "ação única (compat)", espera: 1, json:
                "{\"fala\":\"oi\",\"acao\":\"shell\",\"params\":{\"cmd\":\"echo UNICA\"}}"),
            Caso(nome: "JSON malformado reparável", espera: 1, json:
                "{fala:\"x\", acao:\"shell\", params:{cmd:\"echo REPARADO\"},}"),
            Caso(nome: "ação desconhecida alucinada", espera: 1, json:
                "{\"fala\":\"x\",\"acao\":\"reproduzir_tudo_agora\",\"params\":{}}"),
            Caso(nome: "acoes vazio", espera: 0, json:
                "{\"fala\":\"nada\",\"acoes\":[]}"),
        ]

        Task { @MainActor in
            let router = AgentRouter()
            print("╔══════════════════════════════════════════════════════════╗")
            print("║   SELFTEST — motor de execução sequencial (AgentRouter)   ║")
            print("╚══════════════════════════════════════════════════════════╝")

            for c in casos {
                print("\n=== \(c.nome) (espera \(c.espera) execuções) ===")
                router.debugLog.removeAll()
                let t0 = Date()
                let fala = await router.process(c.json)
                let dt = Date().timeIntervalSince(t0)
                print("  fala: \(fala)")
                print("  lastAction='\(router.lastAction)' lastResult='\(router.lastResult)'")
                print(String(format: "  tempo: %.2fs", dt))
                let exec = router.debugLog.filter { $0.hasPrefix("  [") }
                if !exec.isEmpty { print("  passos: \(exec.count) → \(exec.joined(separator: " ; "))") }
                let summary = router.debugLog.first { $0.contains("Multi resultado") }
                if let s = summary { print("  \(s)") }
            }

            print("\n[SELFTEST] concluído")
            exit(0)
        }
        RunLoop.main.run()
    }
}
