import Foundation

struct ChatMessage: Identifiable, Codable {
    var id = UUID()
    var role: String       // "user" | "assistant" | "system"
    var content: String
    var timestamp = Date()
    var isError = false
}

struct AIResponse {
    var fala: String
    var acao: String
    var params: [String: Any]

    static func from(json: [String: Any]) -> AIResponse {
        AIResponse(
            fala: json["fala"] as? String ?? "",
            acao: json["acao"] as? String ?? "nenhuma",
            params: json["params"] as? [String: Any] ?? [:]
        )
    }
}

struct OllamaTagsResponse: Codable {
    let models: [OllamaModelInfo]
}

struct OllamaModelInfo: Codable {
    let name: String
}

struct OllamaChatResponse: Codable {
    let message: OllamaChatMsg
}

struct OllamaChatMsg: Codable {
    let role: String
    let content: String
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// Streaming chunk from Ollama /api/chat stream:true
struct OllamaStreamChunk: Codable {
    let message: OllamaChatMsg?
    let done: Bool?
}

import SwiftUI
