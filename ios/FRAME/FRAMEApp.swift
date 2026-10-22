import SwiftUI

@main
struct FRAMEApp: App {
    @StateObject private var api: FrameAPI
    @StateObject private var model: AppModel
    init() {
        let host = Bundle.main.object(forInfoDictionaryKey:"FRAMEAPIHost") as? String ?? ""
        let url = host.isEmpty ? nil : URL(string:"https://" + host)
        let service = FrameAPI(baseURL:url)
        _api = StateObject(wrappedValue:service)
        _model = StateObject(wrappedValue:AppModel(api:service))
    }
    var body: some Scene {
        WindowGroup { RootView().environmentObject(api).environmentObject(model) }
    }
}
