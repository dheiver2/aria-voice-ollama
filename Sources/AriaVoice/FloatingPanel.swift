import AppKit
import SwiftUI

// NSPanel sem foco, sempre no topo, com blur nativo
class FloatingPanel: NSPanel {

    init(view: NSView) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 220),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isOpaque          = false
        backgroundColor   = .clear
        level             = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hasShadow         = true
        isMovableByWindowBackground = true
        contentView       = view
        center()
    }

    override var canBecomeKey: Bool { true }

    func show() {
        // Centra na tela principal
        if let screen = NSScreen.main {
            let sw = screen.visibleFrame.width
            let sh = screen.visibleFrame.height
            let ox = screen.visibleFrame.origin.x
            let oy = screen.visibleFrame.origin.y
            setFrameOrigin(NSPoint(
                x: ox + (sw - frame.width) / 2,
                y: oy + sh * 0.62
            ))
        }
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: false)
    }

    func hide() {
        orderOut(nil)
    }
}
