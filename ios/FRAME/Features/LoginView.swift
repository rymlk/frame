import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var api: FrameAPI
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var code = ""
    @State private var codeSent = false
    @State private var busy = false
    @State private var error: String?
    @State private var resendAfter = Date.distantPast
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Ta collection, partout.").font(.title.bold())
                    Text("Connecte-toi ou crée ton compte avec un code reçu par e-mail. Aucun mot de passe à retenir.").foregroundStyle(.secondary)
                }
                Section("Ton adresse e-mail") {
                    TextField("nom@exemple.fr",text:$email).textContentType(.emailAddress).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled().disabled(codeSent || busy)
                }
                if codeSent {
                    Section("Code reçu par e-mail") {
                        TextField("Code de connexion",text:$code).keyboardType(.numberPad).textContentType(.oneTimeCode)
                        Button("Se connecter") { Task { await verify() } }.disabled(code.trimmingCharacters(in:.whitespacesAndNewlines).count<6 || busy)
                        Button("Modifier l’adresse") { codeSent = false; code = "" }.disabled(busy)
                        TimelineView(.periodic(from:.now,by:1)) { context in
                            Button("Renvoyer un code") { Task { await send() } }.disabled(busy || context.date<resendAfter)
                        }
                    }
                } else {
                    Button("Recevoir mon code") { Task { await send() } }.disabled(!email.contains("@") || busy)
                }
                if busy { ProgressView("Un instant…") }
                if let error { Text(error).foregroundStyle(.red).font(.footnote) }
                if let config = api.config {
                    Section { Link("Politique de confidentialité",destination:config.privacyURL); Link("Conditions d’utilisation",destination:config.termsURL) }
                }
            }.navigationTitle("Bienvenue sur FRAME").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement:.cancellationAction) { Button("Fermer") { dismiss() }.disabled(busy) } }
        }.tint(FrameStyle.gold)
    }
    private func send() async {
        busy = true; error = nil; defer { busy = false }
        email = email.trimmingCharacters(in:.whitespacesAndNewlines).lowercased()
        do { try await api.sendCode(email:email); codeSent = true; resendAfter = Date().addingTimeInterval(60) }
        catch { self.error = error.localizedDescription }
    }
    private func verify() async {
        busy = true; error = nil; defer { busy = false }
        do { try await api.verifyCode(email:email,code:code.trimmingCharacters(in:.whitespacesAndNewlines)); dismiss() }
        catch { self.error = "Le code n’a pas pu être validé. Vérifie-le ou demande un nouveau code." }
    }
}
