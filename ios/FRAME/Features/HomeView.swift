import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var api: FrameAPI
    @State private var home: HomePayload?
    @State private var error: String?
    @State private var loading = false
    var body: some View {
        Group {
            if let home {
                ScrollView {
                    VStack(alignment:.leading,spacing:30) {
                        if let lead = home.lead {
                            NavigationLink(value:lead) {
                                ZStack(alignment:.bottomLeading) {
                                    Artwork(url:lead.backdropURL ?? lead.posterURL).frame(height:400)
                                    LinearGradient(colors:[.clear,FrameStyle.background],startPoint:.top,endPoint:.bottom)
                                    VStack(alignment:.leading,spacing:12) {
                                        Text("À L’AFFICHE").font(.caption.weight(.bold)).tracking(3).foregroundStyle(FrameStyle.gold)
                                        Text(lead.title).font(.largeTitle.bold()).multilineTextAlignment(.leading)
                                        Text(lead.overview).font(.subheadline).lineLimit(3).multilineTextAlignment(.leading).foregroundStyle(.secondary)
                                        Label("Découvrir",systemImage:"arrow.up.right").font(.subheadline.bold())
                                    }.padding(24)
                                }.clipped()
                            }.buttonStyle(.plain)
                        }
                        MediaShelf(title:"Films du moment",items:home.films)
                        MediaShelf(title:"Séries à suivre",items:home.shows)
                        MediaShelf(title:"L’univers anime",items:home.animes)
                        Text("Les histoires passent. Ta collection reste.").font(.footnote).foregroundStyle(.secondary).padding(24)
                    }
                }.refreshable { await load() }
            } else if let error { RetryPanel(message:error) { Task { await load() } } }
            else { ProgressView("Le cinéma arrive…").frame(maxWidth:.infinity,maxHeight:.infinity) }
        }.background(FrameStyle.background).navigationTitle("FRAME.").navigationBarTitleDisplayMode(.inline)
            .task { if home == nil { await load() } }
    }
    private func load() async {
        guard !loading else { return }; loading = true; defer { loading = false }
        do { home = try await api.request("/api/home"); error = nil }
        catch { self.error = error.localizedDescription }
    }
}
