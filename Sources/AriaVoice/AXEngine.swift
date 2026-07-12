import AppKit
import ApplicationServices
import CoreGraphics

// MARK: - Motor de Acessibilidade (AXUIElement + CGEvent)

final class AXEngine {

    // MARK: - Obter processo AX de um app rodando

    static func axApp(bundleID: String) -> AXUIElement? {
        NSWorkspace.shared.runningApplications
            .first { $0.bundleIdentifier == bundleID }
            .map { AXUIElementCreateApplication($0.processIdentifier) }
    }

    static func axApp(named name: String) -> AXUIElement? {
        NSWorkspace.shared.runningApplications
            .first { ($0.localizedName ?? "").lowercased().contains(name.lowercased()) }
            .map { AXUIElementCreateApplication($0.processIdentifier) }
    }

    // MARK: - Leitura de atributos

    static func value(_ el: AXUIElement, _ attr: String) -> Any? {
        var val: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(el, attr as CFString, &val)
        return err == .success ? val : nil
    }

    static func stringValue(_ el: AXUIElement, _ attr: String) -> String? {
        value(el, attr) as? String
    }

    static func children(_ el: AXUIElement) -> [AXUIElement] {
        value(el, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }

    static func windows(_ el: AXUIElement) -> [AXUIElement] {
        value(el, kAXWindowsAttribute) as? [AXUIElement] ?? []
    }

    // MARK: - Busca de elementos

    /// Busca recursiva por qualquer atributo + valor (case-insensitive)
    static func find(
        _ root: AXUIElement,
        role: String? = nil,
        subrole: String? = nil,
        description: String? = nil,
        title: String? = nil,
        placeholder: String? = nil,
        depth: Int = 15
    ) -> AXUIElement? {
        guard depth > 0 else { return nil }

        let r   = stringValue(root, kAXRoleAttribute) ?? ""
        let sub = stringValue(root, kAXSubroleAttribute) ?? ""
        let dsc = stringValue(root, kAXDescriptionAttribute) ?? ""
        let ttl = stringValue(root, kAXTitleAttribute) ?? ""
        let ph  = stringValue(root, kAXPlaceholderValueAttribute) ?? ""

        var match = true
        if let role, !r.lowercased().contains(role.lowercased()) { match = false }
        if let sub2 = subrole, !sub.lowercased().contains(sub2.lowercased()) { match = false }
        if let d = description, !dsc.lowercased().contains(d.lowercased()) { match = false }
        if let t = title, !ttl.lowercased().contains(t.lowercased()) { match = false }
        if let p = placeholder, !ph.lowercased().contains(p.lowercased()) { match = false }
        if match { return root }

        for child in children(root) {
            if let found = find(child, role: role, subrole: subrole, description: description,
                                title: title, placeholder: placeholder, depth: depth - 1) {
                return found
            }
        }
        return nil
    }

    /// Busca todos os elementos que satisfazem o predicado
    static func findAll(
        _ root: AXUIElement,
        depth: Int = 12,
        where predicate: (AXUIElement) -> Bool
    ) -> [AXUIElement] {
        guard depth > 0 else { return [] }
        var results: [AXUIElement] = []
        if predicate(root) { results.append(root) }
        for child in children(root) {
            results += findAll(child, depth: depth - 1, where: predicate)
        }
        return results
    }

    // MARK: - Ações

    @discardableResult
    static func press(_ el: AXUIElement) -> Bool {
        AXUIElementPerformAction(el, kAXPressAction as CFString) == .success
    }

    @discardableResult
    static func focus(_ el: AXUIElement) -> Bool {
        AXUIElementSetAttributeValue(el, kAXFocusedAttribute as CFString, true as CFTypeRef) == .success
    }

    @discardableResult
    static func setValue(_ el: AXUIElement, _ text: String) -> Bool {
        AXUIElementSetAttributeValue(el, kAXValueAttribute as CFString, text as CFTypeRef) == .success
    }

    // MARK: - Digitação via CGEvent (funciona mesmo quando AXSetValue falha)

    /// Digita texto no elemento focado usando CGEvent (mais confiável em Electron)
    static func typeText(_ text: String) {
        let src = CGEventSource(stateID: .hidSystemState)
        for char in text {
            let str = String(char)
            // Usa CGEvent com tipo keyDown/keyUp com unicode
            if let down = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true),
               let up   = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false) {
                var utf16 = Array(str.utf16)
                down.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
                up.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
                down.post(tap: .cghidEventTap)
                up.post(tap: .cghidEventTap)
            }
        }
    }

    static func pressEnter() {
        let src = CGEventSource(stateID: .hidSystemState)
        if let down = CGEvent(keyboardEventSource: src, virtualKey: 0x24, keyDown: true),
           let up   = CGEvent(keyboardEventSource: src, virtualKey: 0x24, keyDown: false) {
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
    }

    static func pressKey(_ vk: CGKeyCode, flags: CGEventFlags = []) {
        let src = CGEventSource(stateID: .hidSystemState)
        if let down = CGEvent(keyboardEventSource: src, virtualKey: vk, keyDown: true),
           let up   = CGEvent(keyboardEventSource: src, virtualKey: vk, keyDown: false) {
            down.flags = flags
            up.flags = flags
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
    }

    /// Cmd+tecla
    static func cmdKey(_ vk: CGKeyCode) {
        pressKey(vk, flags: .maskCommand)
    }

    // MARK: - Clicar em posição

    static func click(at point: CGPoint) {
        let src = CGEventSource(stateID: .hidSystemState)
        if let down = CGEvent(mouseEventSource: src, mouseType: .leftMouseDown,
                              mouseCursorPosition: point, mouseButton: .left),
           let up   = CGEvent(mouseEventSource: src, mouseType: .leftMouseUp,
                              mouseCursorPosition: point, mouseButton: .left) {
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
    }

    /// Clica no centro de um elemento AX
    static func clickElement(_ el: AXUIElement) -> Bool {
        if press(el) { return true }
        // Fallback: obter posição e clicar via CGEvent
        if let posVal = value(el, kAXPositionAttribute),
           let sizeVal = value(el, kAXSizeAttribute),
           CFGetTypeID(posVal as CFTypeRef) == AXValueGetTypeID(),
           CFGetTypeID(sizeVal as CFTypeRef) == AXValueGetTypeID() {
            var pos  = CGPoint.zero
            var size = CGSize.zero
            guard AXValueGetValue(posVal as! AXValue, .cgPoint, &pos),
                  AXValueGetValue(sizeVal as! AXValue, .cgSize, &size) else { return false }
            let center = CGPoint(x: pos.x + size.width/2, y: pos.y + size.height/2)
            // AX retorna coordenadas globais com origem no canto superior-esquerdo da
            // tela principal — mesmo espaço usado por CGEvent(mouseEventSource:). Não
            // há necessidade de inverter Y (e NSScreen.main! poderia crashar/errar em
            // configuração multi-monitor).
            click(at: center)
            return true
        }
        return false
    }

    // MARK: - Clipboard paste (mais rápido que digitar char por char)

    static func pasteText(_ text: String, into el: AXUIElement? = nil) {
        let prev = NSPasteboard.general.string(forType: .string)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        Thread.sleep(forTimeInterval: 0.1)
        if let el { focus(el) }
        cmdKey(0x09) // Cmd+V
        // Espera o paste ser consumido pelo app de destino e restaura o clipboard
        // de forma SÍNCRONA (contido neste passo). Nunca agendar com asyncAfter: em
        // cadeias rápidas o timer dispara no meio de um passo posterior e sobrescreve
        // o clipboard que aquele passo acabou de definir (texto trocado/obsoleto).
        Thread.sleep(forTimeInterval: 0.35)
        if let prev {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(prev, forType: .string)
        }
    }

    // MARK: - Verificação de permissão AX

    static var hasAccessibilityPermission: Bool {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }
}

// MARK: - Extensão conveniente para apps específicos

extension AXEngine {

    /// Encontra campo de entrada de texto em qualquer app
    static func findInputField(in axApp: AXUIElement) -> AXUIElement? {
        // Tenta text area primeiro (chat input)
        if let ta = find(axApp, role: "AXTextArea") { return ta }
        // Search field
        if let sf = find(axApp, subrole: "AXSearchField") { return sf }
        if let sf = find(axApp, role: "AXTextField") { return sf }
        return nil
    }

    /// Encontra botão por título/descrição
    static func findButton(in axApp: AXUIElement, named name: String) -> AXUIElement? {
        find(axApp, role: "AXButton", description: name) ??
        find(axApp, role: "AXButton", title: name)
    }
}
