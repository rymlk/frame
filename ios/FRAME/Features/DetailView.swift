import SwiftUI

struct DetailView: View {
    let media: Media
    @EnvironmentObject private var api: FrameAPI
    @EnvironmentObject private var model: AppModel
    @State private var detail: MediaDetail?
    @State private var error: String?
    @State private var reviewPresented = false
    @State private var communityPresented = false
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:24) {
                ZStack(alignment:.bottomLeading) {
                    Artwork(url:media.backdropURL ?? media.posterURL).frame(height:300)
                    LinearGradient(colors:[.clear,FrameStyle.background],startPoint:.top,endPoint:.bottom)
                    Text(media.title).font(.largeTitle.bold()).padding(20)
                }.clipped()
                VStack(alignment:.leading,spacing:24) {
                    HStack {
                        Text([media.year,media.category,media.rating.map { $0 + " ★ TMDB" } ?? ""].filter { !$0.isEmpty }.joined(separator:" · "))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    HStack(spacing:12) {
                        let saved = model.library?.value(media.key,"watchlist")?.bool == true
                        Button { model.set(media,field:"watchlist",value:.bool(!saved)) } label: {
                            Label(saved ? "Dans ma liste" : "Ma liste",systemImage:saved ? "checkmark" : "plus")
                        }.buttonStyle(.borderedProminent)
                        if media.type == "movie" {
                            let watched = model.library?.value(media.key,"watched")?.bool == true
                            Button { model.set(media,field:"watched",value:.bool(!watched),runtime:detail?.runtime) } label: {
                                Label(watched ? "Vu" : "Marquer vu",systemImage:watched ? "checkmark.circle.fill" : "checkmark.circle")
                            }.buttonStyle(.bordered)
                        }
                    }.controlSize(.large)
                    if let detail {
                        if !detail.genres.isEmpty { Text(detail.genres.joined(separator:" · ")).font(.caption).foregroundStyle(FrameStyle.gold) }
                        Text(detail.overview.isEmpty ? "Aucun résumé disponible." : detail.overview).font(.body).textSelection(.enabled)
                        if let runtime = detail.runtime, runtime > 0 { Label("\(runtime) minutes",systemImage:"clock").font(.footnote).foregroundStyle(.secondary) }
                        if let next = detail.nextEpisode {
                            VStack(alignment:.leading,spacing:6) {
                                Text("Prochain épisode").font(.headline)
                                Text("S\(next.season) · E\(next.episode) — \(next.name ?? "À venir")")
                                if let date = next.airDate { Text(date).font(.caption).foregroundStyle(.secondary) }
                            }.padding().frame(maxWidth:.infinity,alignment:.leading).background(FrameStyle.panel,in:RoundedRectangle(cornerRadius:18))
                        }
                        if !detail.seasons.isEmpty {
                            Text("Saisons et épisodes").font(.title2.bold())
                            ForEach(detail.seasons) { season in
                                NavigationLink { SeasonView(media:media,season:season) } label: {
                                    HStack { VStack(alignment:.leading) { Text(season.name).font(.headline); Text("\(season.count) épisodes").font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName:"chevron.right") }
                                        .padding().background(FrameStyle.panel,in:RoundedRectangle(cornerRadius:15))
                                }.buttonStyle(.plain)
                            }
                        }
                        ForEach(detail.videos) { trailer in
                            if let url = youtubeURL(trailer.id) { Link(destination:url) { Label(trailer.name,systemImage:"play.rectangle") }.buttonStyle(.bordered) }
                        }
                    } else if let error { RetryPanel(message:error) { Task { await load() } } }
                    else { ProgressView("Chargement de la fiche…") }
                    Divider()
                    Text("Ton avis").font(.title2.bold())
                    if let rating = model.library?.value(media.key,"rating")?.int { Text(String(repeating:"★",count:max(0,min(5,rating)))).foregroundStyle(FrameStyle.gold).accessibilityLabel("\(rating) étoiles sur 5") }
                    if let review = model.library?.value(media.key,"review")?.string, !review.isEmpty { Text(review).foregroundStyle(.secondary) }
                    Button("Noter et commenter") { if model.requireAccount() { reviewPresented = true } }.buttonStyle(.bordered)
                    if api.config?.communityEnabled == true {
                        Button { communityPresented = true } label: { Label("Voir les discussions",systemImage:"bubble.left.and.bubble.right") }.buttonStyle(.bordered)
                    }
                }.padding(.horizontal,20).padding(.bottom,30)
            }
        }.background(FrameStyle.background).navigationBarTitleDisplayMode(.inline)
            .task { await load() }
            .sheet(isPresented:$reviewPresented) { ReviewSheet(media:media) }
            .sheet(isPresented:$communityPresented) { NavigationStack { CommunityView(media:media).toolbar { ToolbarItem(placement:.confirmationAction) { Button("Fermer") { communityPresented = false } } } } }
    }
    private func load() async {
        do { detail = try await api.request("/api/detail",query:[URLQueryItem(name:"type",value:media.type),URLQueryItem(name:"id",value:String(media.id))]); error = nil }
        catch { self.error = error.localizedDescription }
    }
    private func youtubeURL(_ id: String) -> URL? {
        guard id.range(of:"^[A-Za-z0-9_-]{1,32}$",options:.regularExpression) != nil else { return nil }
        return URL(string:"https://www.youtube.com/watch?v=" + id)
    }
}

struct SeasonView: View {
    let media: Media; let season: SeasonSummary
    @EnvironmentObject private var api: FrameAPI
    @EnvironmentObject private var model: AppModel
    @State private var content: SeasonPayload?
    @State private var error: String?
    @State private var selected: Episode?
    @State private var processing = false
    var body: some View {
        Group {
            if let content {
                List(content.episodes) { episode in
                    let watched = model.library?.value(media.key,episode.field)?["watched"]?.bool == true
                    HStack(alignment:.top,spacing:14) {
                        Button {
                            if watched { toggle(episode,false) } else if model.requireAccount() { selected = episode }
                        } label: {
                            Image(systemName:watched ? "checkmark.circle.fill" : "circle").font(.title2).frame(width:44,height:44)
                        }.buttonStyle(.borderless).disabled(!episode.hasAired || processing)
                            .accessibilityLabel(watched ? "Marquer l’épisode \(episode.number) non vu" : "Marquer l’épisode \(episode.number) vu")
                        VStack(alignment:.leading,spacing:7) {
                            Text("\(episode.number). \(episode.name)").font(.headline)
                            if !episode.description.isEmpty { Text(episode.description).font(.subheadline).foregroundStyle(.secondary) }
                            Text([episode.airDate,episode.runtime.map { "\($0) min" }].compactMap { $0 }.joined(separator:" · ")).font(.caption).foregroundStyle(.secondary)
                            if !episode.hasAired { Text("Pas encore diffusé ou date inconnue").font(.caption).foregroundStyle(FrameStyle.gold) }
                        }
                    }.listRowBackground(FrameStyle.panel)
                }.scrollContentBackground(.hidden)
            } else if let error { RetryPanel(message:error) { Task { await load() } } }
            else { ProgressView("Chargement des épisodes…") }
        }.background(FrameStyle.background).navigationTitle(season.name)
            .task { await load() }
            .confirmationDialog("Mettre à jour ta progression",isPresented:Binding(get:{selected != nil},set:{if !$0 { selected = nil }}),titleVisibility:.visible) {
                if let episode = selected {
                    Button("Cet épisode uniquement") { toggle(episode,true) }
                    if episode.season > 1 || episode.number > 1 { Button("Cet épisode et tous les précédents") { Task { await markThrough(episode) } } }
                }
                Button("Annuler",role:.cancel) { selected = nil }
            }
    }
    private func toggle(_ episode: Episode,_ watched: Bool) {
        model.set(media,field:episode.field,value:.object(["watched":.bool(watched),"runtime":episode.runtime.map { .number(Double($0)) } ?? .null]))
        selected = nil
    }
    private func load() async {
        do { content = try await api.request("/api/season",query:[URLQueryItem(name:"id",value:String(media.id)),URLQueryItem(name:"season",value:String(season.number))]); error = nil }
        catch { self.error = error.localizedDescription }
    }
    private func markThrough(_ episode: Episode) async {
        processing = true; defer { processing = false; selected = nil }
        do {
            let previous: EarlierEpisodes = try await api.request("/api/earlier",query:[URLQueryItem(name:"type",value:"tv"),URLQueryItem(name:"id",value:String(media.id)),URLQueryItem(name:"season",value:String(episode.season)),URLQueryItem(name:"episode",value:String(episode.number))])
            var changes: [(String,JSONValue)] = previous.episodes.map { item in
                ("episode:\(item.season):\(item.number)",.object(["watched":.bool(true),"runtime":item.runtime.map { .number(Double($0)) } ?? .null]))
            }
            changes.append((episode.field,.object(["watched":.bool(true),"runtime":episode.runtime.map { .number(Double($0)) } ?? .null])))
            model.setMany(media,changes:changes)
        } catch { model.message = error.localizedDescription }
    }
}

struct ReviewSheet: View {
    let media: Media
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var rating = 0
    @State private var review = ""
    var body: some View {
        NavigationStack {
            Form {
                Section(media.title) {
                    Picker("Ma note",selection:$rating) { Text("Sans note").tag(0); ForEach(1...5,id:\.self) { Text("\($0) / 5").tag($0) } }
                    TextEditor(text:$review).frame(minHeight:150).accessibilityLabel("Mon avis personnel")
                    Text("\(review.count)/700 · Cet avis reste dans ta collection.").font(.caption).foregroundStyle(.secondary)
                }
            }.navigationTitle("Ton avis").toolbar {
                ToolbarItem(placement:.cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement:.confirmationAction) { Button("Enregistrer") {
                    model.set(media,field:"rating",value:rating == 0 ? .null : .number(Double(rating)))
                    model.set(media,field:"review",value:.string(review)); dismiss()
                }.disabled(review.count>700) }
            }.onAppear { rating = model.library?.value(media.key,"rating")?.int ?? 0; review = model.library?.value(media.key,"review")?.string ?? "" }
        }
    }
}
