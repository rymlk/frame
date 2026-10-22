import SwiftUI

struct DiscoverView: View {
    @EnvironmentObject private var api: FrameAPI
    @State private var query = ""
    @State private var type = "all"
    @State private var items: [Media] = []
    @State private var page = 0
    @State private var pages = 1
    @State private var error: String?
    @State private var loading = false
    @State private var generation = UUID()
    private let columns = [GridItem(.adaptive(minimum:140),spacing:16)]
    var body: some View {
        VStack(spacing:0) {
            Picker("Type d’œuvre",selection:$type) {
                Text("Tout").tag("all"); Text("Films").tag("movie"); Text("Séries").tag("tv"); Text("Animes").tag("anime")
            }.pickerStyle(.segmented).padding()
            ScrollView {
                if items.isEmpty && !loading && error == nil { ContentUnavailableView.search(text:query) }
                LazyVGrid(columns:columns,alignment:.center,spacing:24) {
                    ForEach(items,id:\.key) { media in NavigationLink(value:media) { PosterCard(media:media,width:140) }.buttonStyle(.plain) }
                }.padding(.horizontal)
                if let error { Text(error).font(.footnote).foregroundStyle(.secondary).padding() }
                if loading { ProgressView().padding() }
                else if page < pages || error != nil { Button(error == nil ? "Voir la suite" : "Réessayer") { Task { await load(reset:page == 0) } }.buttonStyle(.bordered).padding() }
            }.refreshable { await load(reset:true) }
        }.background(FrameStyle.background).navigationTitle("Découvrir")
            .searchable(text:$query,prompt:"Film, série ou anime")
            .task(id:query + "/" + type) {
                generation = UUID(); loading = false; items = []; page = 0; error = nil
                do { try await Task.sleep(for:.milliseconds(350)); try Task.checkCancellation(); await load(reset:true) } catch {}
            }
    }
    private func load(reset: Bool) async {
        guard !loading else { return }; loading = true
        let current = generation
        defer { if current == generation { loading = false } }
        let next = reset ? 1 : page + 1
        do {
            let result: MediaPage = try await api.request(query.isEmpty ? "/api/discover" : "/api/search",query:[URLQueryItem(name:"type",value:type),URLQueryItem(name:"q",value:query),URLQueryItem(name:"page",value:String(next))])
            guard current == generation, !Task.isCancelled else { return }
            let existing = reset ? Set<String>() : Set(items.map(\.key))
            items = (reset ? [] : items) + result.items.filter { !existing.contains($0.key) }
            page = result.page; pages = result.totalPages; error = nil
        } catch { if current == generation && !Task.isCancelled { self.error = error.localizedDescription } }
    }
}
