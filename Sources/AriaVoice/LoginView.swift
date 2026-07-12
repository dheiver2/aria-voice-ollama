import SwiftUI

/// Tela de login simples, sem hash e sem persistência: credenciais fixas
/// admin/admin, válidas apenas para a sessão atual do app.
struct LoginView: View {
    var onSuccess: () -> Void

    @State private var username = ""
    @State private var password = ""
    @State private var errorMessage: String? = nil

    private let bg1     = Color(hex: "080810")
    private let bg2     = Color(hex: "0D0820")
    private let accent  = Color(hex: "7C3AED")
    private let accentL = Color(hex: "A78BFA")

    var body: some View {
        ZStack {
            LinearGradient(colors: [bg1, bg2], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                ZStack {
                    Circle().fill(accent.opacity(0.2)).frame(width: 56, height: 56)
                    Text("Ā").font(.system(size: 26, weight: .black, design: .rounded))
                        .foregroundStyle(LinearGradient(colors: [accentL, accent],
                                                       startPoint: .top, endPoint: .bottom))
                }

                Text("ÁRIA").font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(LinearGradient(colors: [.white, accentL],
                                                   startPoint: .leading, endPoint: .trailing))

                VStack(spacing: 12) {
                    TextField("Usuário", text: $username)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled(true)
                        .onSubmit(attemptLogin)

                    SecureField("Senha", text: $password)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(attemptLogin)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 12))
                            .foregroundColor(Color(hex: "EF4444"))
                    }

                    Button(action: attemptLogin) {
                        Text("Entrar")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
                }
                .frame(width: 240)
            }
            .padding(32)
        }
        .frame(minWidth: 520, idealWidth: 560, maxWidth: 700,
               minHeight: 700, idealHeight: 760)
    }

    private func attemptLogin() {
        if username == "admin" && password == "admin" {
            errorMessage = nil
            onSuccess()
        } else {
            errorMessage = "Usuário ou senha incorretos"
        }
    }
}
