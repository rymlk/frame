import SwiftUI

struct RootView: View {
    @EnvironmentObject private var api: FrameAPI
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        TabView {
            NavigationStack { HomeView().navigationDestination(for:Media.self) { DetailView(media:$0) } }
                .tabItem { Label("Accueil",systemImage:"house") }
            NavigationStack { DiscoverView().navigationDestination(for:Media.self) { DetailView(media:$0) } }
                .tabItem { Label("Découvrir",systemImage:"magnifyingglass") }
            NavigationStack { LibraryView().navigationDestination(for:Media.self) { DetailView(media:$0) } }
                .tabItem { Label("Collection",systemImage:"rectangle.stack") }
            NavigationStack { CommunityView(media:nil) }
                .tabItem { Label("Communauté",systemImage:"bubble.left.and.bubble.right") }
            NavigationStack { ProfileView() }
                .tabItem { Label("Profil",systemImage:"person.crop.circle") }
        }
        .tint(FrameStyle.gold).preferredColorScheme(.dark)
        .sheet(isPresented:$model.loginPresented) { LoginView() }
        .alert("FRAME",isPresented:Binding(get:{ model.message != nil },set:{ if !$0 { model.message = nil } })) {
            Button("OK",role:.cancel) { model.message = nil }
        } message: { Text(model.message ?? "") }
        .safeAreaInset(edge:.top,spacing:0) {
            if model.offline { Text("Hors connexion · ta collection reste disponible").font(.caption).frame(maxWidth:.infinity).padding(8).background(FrameStyle.panel) }
        }
        .task { await model.start() }
        .onChange(of:api.session?.user.id) { _,_ in model.changeAccount(); Task { if api.session != nil { await model.loadProfile() } } }
        .onChange(of:scenePhase) { _,phase in if phase == .active { model.sync() } }
    }
}
