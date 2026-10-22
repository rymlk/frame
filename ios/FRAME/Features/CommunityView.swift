import SwiftUI

struct CommunityView: View {
    let media: Media?
    @EnvironmentObject private var api: FrameAPI
    @EnvironmentObject private var model: AppModel
    @State private var posts: [CommunityPost] = []
    @State private var loading = false
    @State private var loaded = false
    @State private var error: String?
    @State private var composing = false
    @State private var reporting: CommunityPost?
    @State private var reason = ""
    var body: some View {
        Group {
            if api.config?.communityEnabled != true {
                ContentUnavailableView("À bientôt dans la communauté",systemImage:"bubble.left.and.bubble.right",description:Text("Les discussions ouvriront prochainement."))
            } else if api.session == nil { LoginPrompt(title:"Parlons cinéma",detail:"Connecte-toi pour lire et partager des avis dans la communauté.") }
            else {
                List {
                    if media == nil {
                        Section { Text("Partage un avis depuis la fiche d’un film ou d’une série.").font(.subheadline).foregroundStyle(.secondary) }
                    }
                    if loading { ProgressView("Chargement des discussions…") }
                    if let error { Section { Text(error).foregroundStyle(.secondary); Button("Réessayer") { Task { await load() } } } }
                    if loaded && posts.isEmpty { ContentUnavailableView("La conversation commence ici",systemImage:"bubble.left",description:Text("Les avis sont vérifiés avant leur publication.")) }
                    ForEach(posts) { post in
                        VStack(alignment:.leading,spacing:12) {
                            HStack {
                                Circle().fill(FrameStyle.avatar(post.avatar)).frame(width:12,height:12)
                                Text(post.nickname).font(.headline)
                                Spacer()
                                Menu {
                                    Button("Signaler",systemImage:"flag") { reporting = post; reason = "" }
                                    if post.authorID != api.session?.user.id {
                                        Button("Bloquer cet utilisateur",systemImage:"person.crop.circle.badge.xmark",role:.destructive) { Task { await block(post) } }
                                    }
                                } label: { Image(systemName:"ellipsis").frame(width:44,height:44) }.accessibilityLabel("Actions sur le message de \(post.nickname)")
                            }
                            if let rating = post.rating { Text(String(repeating:"★",count:max(0,min(5,rating)))).foregroundStyle(FrameStyle.gold).accessibilityLabel("\(rating) étoiles sur 5") }
                            Text(post.content).textSelection(.enabled)
                            if let date = post.createdAt.split(separator:"T").first { Text(String(date)).font(.caption).foregroundStyle(.secondary) }
                        }.padding(.vertical,8).listRowBackground(FrameStyle.panel)
                    }
                }.scrollContentBackground(.hidden).refreshable { await load() }
            }
        }.background(FrameStyle.background).navigationTitle(media == nil ? "Communauté" : "Discussions")
            .toolbar { if media != nil && api.config?.communityEnabled == true { ToolbarItem(placement:.primaryAction) { Button("Écrire",systemImage:"square.and.pencil") { if model.requireAccount() { composing = true } } } } }
            .task(id:api.session?.user.id) { if api.config?.communityEnabled == true && api.session != nil { await load() } }
            .onChange(of:api.config?.communityEnabled) { _,enabled in if enabled == true && api.session != nil { Task { await load() } } }
            .sheet(isPresented:$composing) { if let media { ComposePostView(media:media) { Task { await load() } } } }
            .alert("Signaler ce message",isPresented:Binding(get:{reporting != nil},set:{if !$0 { reporting = nil }})) {
                TextField("Motif du signalement",text:$reason)
                Button("Envoyer") { if let post = reporting { Task { await report(post) } } }.disabled(reason.trimmingCharacters(in:.whitespaces).isEmpty || reason.count>500)
                Button("Annuler",role:.cancel) { reporting = nil }
            } message: { Text("Le signalement sera transmis à la modération.") }
    }
    private func load() async {
        guard !loading else { return }; loading = true; defer { loading = false }
        do { posts = try await api.request("/v1/community",query:media.map { [URLQueryItem(name:"mediaKey",value:$0.key)] } ?? [],authenticated:true); error = nil; loaded = true }
        catch { self.error = error.localizedDescription }
    }
    private func report(_ post: CommunityPost) async {
        struct Report: Encodable { let postID: UUID; let reason: String }
        do { let _: Empty = try await api.request("/v1/reports",method:"POST",body:Report(postID:post.id,reason:reason)); model.message = "Signalement envoyé. Merci." }
        catch { model.message = error.localizedDescription }
        reporting = nil
    }
    private func block(_ post: CommunityPost) async {
        struct Block: Encodable { let userID: UUID; let blocked = true }
        do { let _: Empty = try await api.request("/v1/blocks",method:"POST",body:Block(userID:post.authorID)); await load() }
        catch { model.message = error.localizedDescription }
    }
}

struct ComposePostView: View {
    let media: Media; let completion: () -> Void
    @EnvironmentObject private var api: FrameAPI
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var content = ""
    @State private var rating = 0
    @State private var accepted = false
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section(media.title) {
                    TextEditor(text:$content).frame(minHeight:180).accessibilityLabel("Ton message public")
                    Text("\(content.count)/700 caractères").font(.caption).foregroundStyle(.secondary)
                    Picker("Note",selection:$rating) { Text("Sans note").tag(0); ForEach(1...5,id:\.self) { Text("\($0) / 5").tag($0) } }
                }
                Section {
                    Toggle("J’accepte les règles de la communauté",isOn:$accepted)
                    if let config = api.config { Link("Lire les règles",destination:config.termsURL); Link("Contacter l’assistance",destination:config.supportURL) }
                    Text("Pas de harcèlement, de propos haineux ou de contenu illégal. Chaque message est vérifié avant d’être visible.").font(.footnote).foregroundStyle(.secondary)
                }
                if let error { Text(error).foregroundStyle(.red) }
            }.navigationTitle("Partager un avis").toolbar {
                ToolbarItem(placement:.cancellationAction) { Button("Annuler") { dismiss() }.disabled(busy) }
                ToolbarItem(placement:.confirmationAction) { Button("Envoyer") { Task { await submit() } }.disabled(busy || !accepted || content.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || content.count>700) }
            }.onAppear { accepted = model.profile?.acceptedTermsVersion == api.config?.termsVersion }
        }
    }
    private func submit() async {
        struct Consent: Encodable { let nickname: String; let bio: String; let avatar: String; let acceptTerms = true }
        struct Post: Encodable { let mediaKey: String; let content: String; let rating: Int? }
        busy = true; defer { busy = false }
        do {
            let profile: Profile = try await api.request("/v1/profile",method:"PATCH",body:Consent(nickname:model.profile?.nickname ?? "Spectateur",bio:model.profile?.bio ?? "",avatar:model.profile?.avatar ?? "indigo"))
            model.profile = profile
            let _: JSONValue = try await api.request("/v1/community",method:"POST",body:Post(mediaKey:media.key,content:content,rating:rating == 0 ? nil : rating))
            dismiss(); completion(); model.message = "Ton avis a été envoyé. Il sera visible après vérification."
        } catch { self.error = error.localizedDescription }
    }
}

struct BlockedUsersView: View {
    @EnvironmentObject private var api: FrameAPI
    @EnvironmentObject private var model: AppModel
    @State private var users: [BlockedUser] = []
    @State private var loading = true
    @State private var error: String?
    var body: some View {
        List {
            if loading { ProgressView() }
            else if let error { Text(error); Button("Réessayer") { Task { await load() } } }
            else if users.isEmpty { Text("Aucun utilisateur bloqué.").foregroundStyle(.secondary) }
            ForEach(users) { user in
                HStack { Text(user.nickname ?? "Utilisateur bloqué"); Spacer(); Button("Débloquer") { Task { await unblock(user) } }.buttonStyle(.borderless) }
            }
        }.navigationTitle("Utilisateurs bloqués").task { await load() }
    }
    private func load() async {
        loading = true; defer { loading = false }
        do { users = try await api.request("/v1/blocks",authenticated:true); error = nil }
        catch { self.error = error.localizedDescription }
    }
    private func unblock(_ user: BlockedUser) async {
        struct Block: Encodable { let userID: UUID; let blocked = false }
        do { let _: Empty = try await api.request("/v1/blocks",method:"POST",body:Block(userID:user.blockedID)); await load() }
        catch { model.message = error.localizedDescription }
    }
}
