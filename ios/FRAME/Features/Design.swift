import SwiftUI

enum FrameStyle {
    static let background = Color(red:8/255,green:9/255,blue:11/255)
    static let panel = Color(red:20/255,green:22/255,blue:26/255)
    static let gold = Color(red:201/255,green:169/255,blue:138/255)
    static func avatar(_ name: String) -> Color {
        switch name { case "rose": return .pink; case "amber": return .orange; case "mint": return .mint; default: return .indigo }
    }
}
struct Artwork: View {
    let url: URL?
    var body: some View {
        AsyncImage(url:url) { phase in
            if let image = phase.image { image.resizable().scaledToFill() }
            else { Rectangle().fill(FrameStyle.panel).overlay { Image(systemName:"film").font(.largeTitle).foregroundStyle(FrameStyle.gold.opacity(0.6)) } }
        }.clipped().accessibilityHidden(true)
    }
}
struct PosterCard: View {
    let media: Media
    var width: CGFloat = 132
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            Artwork(url:media.posterURL).frame(width:width,height:width*1.5).clipShape(RoundedRectangle(cornerRadius:15))
            Text(media.title).font(.subheadline.weight(.semibold)).lineLimit(2).frame(height:38,alignment:.topLeading)
            Text([media.year,media.category].filter { !$0.isEmpty }.joined(separator:" · ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }.frame(width:width,alignment:.leading)
            .accessibilityElement(children:.ignore).accessibilityLabel("\(media.title), \(media.category), \(media.year)")
    }
}
struct MediaShelf: View {
    let title: String; let items: [Media]
    var body: some View {
        VStack(alignment:.leading,spacing:14) {
            Text(title).font(.title2.bold()).padding(.horizontal,20).accessibilityAddTraits(.isHeader)
            ScrollView(.horizontal) {
                LazyHStack(alignment:.top,spacing:14) {
                    ForEach(items,id:\.key) { media in NavigationLink(value:media) { PosterCard(media:media) }.buttonStyle(.plain) }
                }.padding(.horizontal,20)
            }.scrollIndicators(.hidden)
        }
    }
}
struct RetryPanel: View {
    let message: String; let retry: () -> Void
    var body: some View {
        ContentUnavailableView {
            Label("Impossible de charger",systemImage:"wifi.exclamationmark")
        } description: { Text(message) } actions: { Button("Réessayer",action:retry).buttonStyle(.borderedProminent) }
    }
}
struct LoginPrompt: View {
    let title: String; let detail: String
    @EnvironmentObject private var model: AppModel
    var body: some View {
        ContentUnavailableView {
            Label(title,systemImage:"person.crop.circle")
        } description: { Text(detail) } actions: {
            Button("Se connecter") { model.loginPresented = true }.buttonStyle(.borderedProminent)
        }
    }
}
