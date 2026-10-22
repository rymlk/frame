import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var api: FrameAPI
    @EnvironmentObject private var model: AppModel
    @State private var editing = false
    @State private var deleting = false
    @State private var signingOut = false
    @State private var busy = false
    var body: some View {
        Group {
            if api.session == nil { LoginPrompt(title:"Ton espace cinéma",detail:"Personnalise ton profil et garde ta progression synchronisée.") }
            else {
                List {
                    Section {
                        HStack(spacing:18) {
                            Text(String((model.profile?.nickname ?? "Spectateur").prefix(1)).uppercased()).font(.largeTitle.bold()).frame(width:72,height:72).background(FrameStyle.avatar(model.profile?.avatar ?? "indigo"),in:Circle())
                            VStack(alignment:.leading,spacing:7) {
                                Text(model.profile?.nickname ?? "Spectateur").font(.title2.bold())
                                if let bio = model.profile?.bio, !bio.isEmpty { Text(bio).font(.subheadline).foregroundStyle(.secondary) }
                            }
                        }.padding(.vertical,10)
                        Button("Modifier mon profil") { editing = true }
                    }
                    Section("Mon cinéma en chiffres") {
                        LabeledContent("Œuvres dans ma collection",value:String(model.library?.savedMedia.count ?? 0))
                        LabeledContent("Films marqués vus",value:String(model.library?.mediaKeys.filter { $0.hasPrefix("movie:") && model.library?.value($0,"watched")?.bool == true }.count ?? 0))
                        LabeledContent("Épisodes vus",value:String(model.library?.watchedEpisodes ?? 0))
                        let minutes = model.library?.watchMinutes ?? 0
                        LabeledContent("Temps renseigné",value:"\(minutes/60) h \(minutes%60) min")
                        Text("Les durées indisponibles ne sont pas comptées.").font(.caption).foregroundStyle(.secondary)
                    }
                    Section("Mon compte") {
                        if let email = api.session?.user.email { Text(email).foregroundStyle(.secondary) }
                        NavigationLink("Utilisateurs bloqués") { BlockedUsersView() }
                        Button("Synchroniser maintenant") { model.sync() }.disabled(model.syncing)
                        Button("Se déconnecter") { signingOut = true }.disabled(busy)
                        Button("Supprimer mon compte",role:.destructive) { deleting = true }.disabled(busy)
                    }
                    Section("À propos") {
                        if let config = api.config {
                            Link("Confidentialité",destination:config.privacyURL)
                            Link("Conditions d’utilisation",destination:config.termsURL)
                            Link("Contacter l’assistance",destination:config.supportURL)
                        }
                        Link("Données et images : TMDB",destination:URL(string:"https://www.themoviedb.org")!)
                        Text("This product uses the TMDB API but is not endorsed or certified by TMDB.").font(.caption).foregroundStyle(.secondary)
                        Text("FRAME 1.0 · \(Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? "1")").font(.caption).foregroundStyle(.secondary)
                    }
                    if busy { ProgressView() }
                }.scrollContentBackground(.hidden).refreshable { await model.loadProfile(); model.sync() }
            }
        }.background(FrameStyle.background).navigationTitle("Profil")
            .sheet(isPresented:$editing) { EditProfileView() }
            .confirmationDialog("Supprimer définitivement ton compte ?",isPresented:$deleting,titleVisibility:.visible) {
                Button("Supprimer mon compte et mes données",role:.destructive) { Task { busy = true; await model.deleteAccount(); busy = false } }
                Button("Annuler",role:.cancel) {}
            } message: { Text("Ton profil, ta collection, ta progression et tes messages seront supprimés. Cette action est irréversible.") }
            .confirmationDialog("Se déconnecter ?",isPresented:$signingOut,titleVisibility:.visible) {
                Button("Se déconnecter",role:.destructive) { Task { busy = true; await model.signOut(); busy = false } }
            } message: { Text((model.library?.pending.isEmpty == false) ? "Des modifications ne sont pas encore synchronisées. Elles seront effacées de cet appareil si tu te déconnectes." : "La copie de ta collection sur cet appareil sera effacée. Tu la retrouveras à ta prochaine connexion.") }
    }
}

struct EditProfileView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var api: FrameAPI
    @Environment(\.dismiss) private var dismiss
    @State private var nickname = ""
    @State private var bio = ""
    @State private var avatar = "indigo"
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("Profil") {
                    TextField("Pseudo",text:$nickname).textContentType(.nickname)
                    TextField("Quelques mots sur toi",text:$bio,axis:.vertical).lineLimit(3...5)
                    Picker("Couleur",selection:$avatar) { Text("Indigo").tag("indigo"); Text("Rose").tag("rose"); Text("Ambre").tag("amber"); Text("Menthe").tag("mint") }
                    Text("Pseudo : 24 caractères. Présentation : 240 caractères.").font(.caption).foregroundStyle(.secondary)
                }
                if let error { Text(error).foregroundStyle(.red) }
            }.navigationTitle("Mon profil").toolbar {
                ToolbarItem(placement:.cancellationAction) { Button("Annuler") { dismiss() }.disabled(busy) }
                ToolbarItem(placement:.confirmationAction) { Button("Enregistrer") { Task { await save() } }.disabled(busy || nickname.trimmingCharacters(in:.whitespaces).isEmpty || nickname.count>24 || bio.count>240) }
            }.onAppear { nickname = model.profile?.nickname ?? "Spectateur"; bio = model.profile?.bio ?? ""; avatar = model.profile?.avatar ?? "indigo" }
        }
    }
    private func save() async {
        struct Update: Encodable { let nickname: String; let bio: String; let avatar: String; let acceptTerms = false }
        busy = true; defer { busy = false }
        do { let profile: Profile = try await api.request("/v1/profile",method:"PATCH",body:Update(nickname:nickname,bio:bio,avatar:avatar)); model.profile = profile; dismiss() }
        catch { self.error = error.localizedDescription }
    }
}
