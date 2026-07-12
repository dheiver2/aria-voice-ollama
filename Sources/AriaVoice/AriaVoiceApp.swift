import SwiftUI
import AppKit

/// Ponto de entrada: desvia para o harness de teste se chamado com --selftest
/// (sem instanciar VoiceManager/ContentView → não dispara TCC de microfone).
@main
struct Entry {
    static func main() {
        if CommandLine.arguments.contains("--selftest") {
            SelfTest.run()   // chama exit(0) ao terminar
            return
        }
        if CommandLine.arguments.contains("--testllm") {
            SelfTestLLM.run()   // teste ao vivo do Ollama; chama exit() ao terminar
            return
        }
        AriaVoiceApp.main()
    }
}

struct AriaVoiceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var isAuthenticated = false

    var body: some Scene {
        WindowGroup {
            Group {
                if isAuthenticated {
                    ContentView()
                } else {
                    LoginView(onSuccess: { isAuthenticated = true })
                }
            }
            .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        if let window = NSApplication.shared.windows.first {
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.backgroundColor = NSColor(red: 0.03, green: 0.03, blue: 0.06, alpha: 1)
        }
    }
}
