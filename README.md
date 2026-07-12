# AriaVoice

Assistente de voz nativa para macOS (Swift/SwiftUI) com LLM local via
[Ollama](https://ollama.com). Fala em português (pt-BR), ouve pelo microfone e
executa ações no Mac através de uma arquitetura de agentes — tudo 100% local,
sem nuvem.

## Funcionalidades

- Reconhecimento de voz pt-BR on-device (`SFSpeechRecognizer`) e síntese de fala.
- Chat com streaming via Ollama (`OllamaService`).
- Orb flutuante e painel de conversa (`FloatingPanel`/`OrbView`).
- 6 agentes roteados por intenção (`AgentRouter`, ~40 intents):
  - **AppAgent** — abrir/fechar aplicativos.
  - **SystemAgent** — volume, brilho, screenshot, dark mode, bateria, lock, sleep.
  - **MessagingAgent** — WhatsApp/Telegram via acessibilidade (AXEngine).
  - **WebAgent** — web, busca, YouTube.
  - **MediaAgent** — controle de mídia.
  - **ShellAgent** — comandos de shell com allowlist e bloqueio de metacaracteres.

## Requisitos

- macOS 13+
- [Ollama](https://ollama.com) rodando localmente (`ollama serve`) com um modelo
  baixado (ex.: `ollama pull llama3.2`).
- Permissões de Microfone, Reconhecimento de Fala, Acessibilidade e Apple Events
  (solicitadas no primeiro uso).

## Build e execução

```bash
./build.sh    # compila release, monta o AriaVoice.app, assina e instala
open ~/Desktop/AriaVoice.app
```

A assinatura usa uma identidade "Apple Development" local (com fallback ad-hoc)
para manter o TCC estável entre rebuilds.

## Testes (smoke)

```bash
swift run AriaVoice --selftest   # encadeamento do AgentRouter
swift run AriaVoice --testllm    # integração viva com o Ollama
```

## Estrutura

```
Sources/AriaVoice/
├── AriaVoiceApp.swift      # entrada
├── ContentView.swift       # UI principal
├── OllamaService.swift     # streaming LLM
├── VoiceManager.swift      # STT pt-BR
├── SpeechOutput.swift      # TTS
├── AXEngine.swift          # acessibilidade
├── FloatingPanel/OrbView   # UI flutuante
└── Agents/                 # AgentRouter + 6 agentes
```

## Limitações conhecidas

- Login local simbólico (não é segurança real).
- Sem persistência de histórico de conversa entre sessões.
- Automação de mensageiros depende da UI dos apps de terceiros (frágil a
  mudanças de layout).
