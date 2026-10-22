import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var api: FrameAPI
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var filter = "all"
    @State private var type = "all"
    @State private var spatial = false
    private var items: [Media] {
        (model.library?.savedMedia ?? []).filter { media in
            let matchesType = type == "all" || (type == "anime" ? media.category == "anime" : media.type == type && media.category != "anime")
            let matchesStatus: Bool
            switch filter {
            case "watchlist": matchesStatus = model.library?.value(media.key,"watchlist")?.bool == true
            case "watched": matchesStatus = model.library?.value(media.key,"watched")?.bool == true
            case "progress": matchesStatus = model.library?.hasWatchedEpisodes(media.key) == true
            default: matchesStatus = true
            }
            return matchesType && matchesStatus
        }
    }
    var body: some View {
        Group {
            if api.session == nil { LoginPrompt(title:"Ta collection",detail:"Retrouve tes films, séries et épisodes sur tous tes appareils.") }
            else {
                VStack(spacing:12) {
                    Picker("Collection",selection:$filter) { Text("Tout").tag("all"); Text("À voir").tag("watchlist"); Text("Vus").tag("watched"); Text("En cours").tag("progress") }.pickerStyle(.segmented).padding(.horizontal)
                    HStack {
                        Picker("Type",selection:$type) { Text("Tous les types").tag("all"); Text("Films").tag("movie"); Text("Séries").tag("tv"); Text("Animes").tag("anime") }
                        Spacer()
                        if model.syncing { ProgressView().accessibilityLabel("Synchronisation") }
                        Button { model.sync() } label: { Image(systemName:"arrow.triangle.2.circlepath").frame(width:44,height:44) }.accessibilityLabel("Synchroniser la collection")
                    }.padding(.horizontal)
                    if let count = model.library?.pending.count, count > 0 { Text("\(count) modification(s) en attente de synchronisation").font(.caption).foregroundStyle(.secondary) }
                    if items.isEmpty { ContentUnavailableView("Rien pour le moment",systemImage:"rectangle.stack",description:Text("Ajoute des œuvres depuis Découvrir ou change les filtres.")) }
                    else if spatial {
                        ScrollView(.horizontal) {
                            LazyHStack(spacing:28) {
                                ForEach(items,id:\.key) { media in
                                    NavigationLink(value:media) { PosterCard(media:media,width:220) }.buttonStyle(.plain)
                                        .scrollTransition(.interactive,axis:.horizontal) { content,phase in
                                            content.scaleEffect(reduceMotion ? 1 : (phase.isIdentity ? 1 : 0.9))
                                                .rotation3DEffect(.degrees(reduceMotion ? 0 : Double(phase.value)*(-18)),axis:(x:0,y:1,z:0))
                                        }
                                }
                            }.scrollTargetLayout().padding(.horizontal,60).padding(.vertical,30)
                        }.scrollTargetBehavior(.viewAligned).scrollIndicators(.hidden)
                    } else {
                        List(items,id:\.key) { media in
                            NavigationLink(value:media) {
                                HStack(spacing:15) {
                                    Artwork(url:media.posterURL).frame(width:58,height:87).clipShape(RoundedRectangle(cornerRadius:8))
                                    VStack(alignment:.leading,spacing:6) { Text(media.title).font(.headline); Text("\(media.year) · \(media.category)").font(.caption).foregroundStyle(.secondary) }
                                }.padding(.vertical,4)
                            }.listRowBackground(FrameStyle.panel)
                        }.scrollContentBackground(.hidden).refreshable { model.sync() }
                    }
                }
            }
        }.background(FrameStyle.background).navigationTitle("Collection")
            .toolbar { ToolbarItem(placement:.primaryAction) { Button { spatial.toggle() } label: { Image(systemName:spatial ? "list.bullet" : "square.stack.3d.up") }.accessibilityLabel(spatial ? "Afficher la liste" : "Afficher le carrousel 3D") } }
    }
}
