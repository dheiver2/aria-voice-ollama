import Foundation
import AppKit
import ApplicationServices

/// Envia mensagens no WhatsApp e Telegram
/// Estratégia: URL scheme → AX direto → System Events
final class MessagingAgent {

    // MARK: - API pública

    @discardableResult
    func send(app: String, contact: String, message: String) -> String {
        let a = app.lowercased()
        if a.contains("whatsapp") || a.contains("zap") || a.contains("wpp") {
            return sendWhatsApp(contact: contact, message: message)
        } else if a.contains("telegram") || a.contains("tele") {
            return sendTelegram(contact: contact, message: message)
        }
        return "⚠️ App '\(app)' não suportado para mensagens."
    }

    @discardableResult
    func openChat(app: String, contact: String) -> String {
        let a = app.lowercased()
        let appName = a.contains("telegram") ? "Telegram" : "WhatsApp"
        return openConversation(appName: appName, bundleID: bundleID(for: appName), contact: contact)
    }

    // MARK: - WhatsApp

    private func sendWhatsApp(contact: String, message: String) -> String {
        // Estratégia 1: URL scheme com número de telefone
        if isPhone(contact) {
            let phone = contact.filter { $0.isNumber || $0 == "+" }
            if let url = URL(string: "whatsapp://send?phone=\(phone)&text=\(encode(message))") {
                NSWorkspace.shared.open(url)
                return "✅ Mensagem enviada para \(contact) no WhatsApp."
            }
        }

        // Estratégia 2: Automação via System Events + CGEvent
        return sendViaAutomation(
            appName: "WhatsApp",
            bundleID: "net.whatsapp.WhatsApp",
            contact: contact,
            message: message
        )
    }

    // MARK: - Telegram

    private func sendTelegram(contact: String, message: String) -> String {
        // Estratégia 1: URL scheme — só quando o contato é explicitamente um @username.
        // (Um nome de exibição como "João Silva" NÃO é um username; tratá-lo como tal
        //  abriria um tg://resolve inválido em vez de buscar a conversa.)
        if contact.hasPrefix("@") {
            let username = String(contact.dropFirst())
            if !username.contains(" "), username.count >= 3,
               let url = URL(string: "tg://resolve?domain=\(username)") {
                NSWorkspace.shared.open(url)
                Thread.sleep(forTimeInterval: 1.5)
                // Depois de abrir o chat, digitar e enviar
                typeAndSend(message)
                return "✅ Mensagem enviada para \(contact) no Telegram."
            }
        }

        // Estratégia 2: Automação
        return sendViaAutomation(
            appName: "Telegram",
            bundleID: "com.tdesktop.Telegram",
            contact: contact,
            message: message
        )
    }

    // MARK: - Automação principal (System Events + CGEvent)

    private func sendViaAutomation(appName: String, bundleID: String, contact: String, message: String) -> String {
        // Abre o app
        let openResult = shell("/usr/bin/open -a \"\(appName)\" 2>&1")
        if openResult.lowercased().contains("unable") {
            return "⚠️ Não foi possível abrir o \(appName)."
        }
        Thread.sleep(forTimeInterval: 1.2)

        // Ativa e traz para frente
        NSWorkspace.shared.runningApplications
            .first { $0.bundleIdentifier == bundleID }?
            .activate(options: .activateIgnoringOtherApps)
        Thread.sleep(forTimeInterval: 0.5)

        // Abre busca de conversa (Cmd+F)
        AXEngine.cmdKey(0x03) // Cmd+F
        Thread.sleep(forTimeInterval: 0.8)

        // Digita o nome do contato via clipboard (mais rápido e confiável)
        AXEngine.pasteText(contact)
        Thread.sleep(forTimeInterval: 1.8) // aguarda resultados

        // Seleciona primeiro resultado (Enter ou Down+Enter)
        AXEngine.pressEnter()
        Thread.sleep(forTimeInterval: 0.8)

        // Agora o campo de mensagem deve estar ativo — digita e envia
        typeAndSend(message)

        return "✅ Mensagem enviada para \(contact) no \(appName)."
    }

    // MARK: - Digitar e enviar (campo de mensagem já focado)

    private func typeAndSend(_ message: String) {
        // Usa clipboard paste para mensagem (mais rápido que CGEvent char por char)
        AXEngine.pasteText(message)
        Thread.sleep(forTimeInterval: 0.3)
        AXEngine.pressEnter()
    }

    // MARK: - Abrir conversa sem enviar

    private func openConversation(appName: String, bundleID: String, contact: String) -> String {
        shell("/usr/bin/open -a \"\(appName)\" 2>&1")
        Thread.sleep(forTimeInterval: 1.2)
        NSWorkspace.shared.runningApplications
            .first { $0.bundleIdentifier == bundleID }?
            .activate(options: .activateIgnoringOtherApps)
        Thread.sleep(forTimeInterval: 0.5)

        AXEngine.cmdKey(0x03) // Cmd+F
        Thread.sleep(forTimeInterval: 0.8)
        AXEngine.pasteText(contact)
        Thread.sleep(forTimeInterval: 1.8)
        AXEngine.pressEnter()

        return "✅ Conversa com \(contact) aberta no \(appName)."
    }

    // MARK: - AppAgent direto via AX (para apps nativos)

    /// Controla qualquer app nativo via AX: clica botões, preenche campos
    func clickButton(appName: String, buttonTitle: String) -> String {
        guard let axApp = AXEngine.axApp(named: appName) else {
            return "⚠️ \(appName) não está rodando."
        }
        guard let btn = AXEngine.findButton(in: axApp, named: buttonTitle) else {
            return "⚠️ Botão '\(buttonTitle)' não encontrado em \(appName)."
        }
        _ = AXEngine.clickElement(btn)
        return "✅ Clicado: \(buttonTitle) em \(appName)."
    }

    func fillField(appName: String, placeholder: String, value: String) -> String {
        guard let axApp = AXEngine.axApp(named: appName) else {
            return "⚠️ \(appName) não está rodando."
        }
        if let field = AXEngine.find(axApp, role: "AXTextField", placeholder: placeholder) ??
                       AXEngine.find(axApp, role: "AXTextArea", placeholder: placeholder) {
            AXEngine.focus(field)
            AXEngine.pasteText(value, into: field)
            return "✅ Campo '\(placeholder)' preenchido em \(appName)."
        }
        return "⚠️ Campo '\(placeholder)' não encontrado em \(appName)."
    }

    // MARK: - Helpers

    private func isPhone(_ s: String) -> Bool {
        let digits = s.filter { $0.isNumber }
        return digits.count >= 8
    }

    private func encode(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s
    }

    private func bundleID(for app: String) -> String {
        switch app.lowercased() {
        case "whatsapp": return "net.whatsapp.WhatsApp"
        case "telegram": return "com.tdesktop.Telegram"
        default: return ""
        }
    }
}
