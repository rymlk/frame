import SwiftUI
import Network
import Combine

@MainActor
final class AppModel: ObservableObject {
    let api: FrameAPI
    @Published var library: LibraryStore?
    @Published var message: String?
    @Published var loginPresented = false
    @Published private(set) var syncing = false
    @Published private(set) var offline = false
    @Published var profile: Profile?
    private let monitor = NWPathMonitor()
    private let directory: URL
    private var syncTask: Task<Void,Never>?
    private var libraryChanges: AnyCancellable?
    private var syncGeneration = UUID()

    init(api: FrameAPI) {
        self.api = api
        directory = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("FRAME/Library",isDirectory:true)
        changeAccount()
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else { return }
                offline = path.status != .satisfied
                if !offline { sync() }
            }
        }
        monitor.start(queue:DispatchQueue(label:"frame.network"))
    }
    func changeAccount() {
        syncGeneration = UUID(); syncTask?.cancel(); syncTask = nil; syncing = false; profile = nil; libraryChanges = nil; library = nil
        guard let id = api.session?.user.id else { return }
        do {
            library = try LibraryStore(directory:directory,accountID:id)
            libraryChanges = library?.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        }
        catch { message = "Impossible de lire ta collection locale. Elle a été conservée ; réessaie après avoir redémarré FRAME." }
        sync()
    }
    func start() async {
        do { try await api.loadConfig(); if api.session != nil { await loadProfile(); sync() } }
        catch { if api.config == nil { message = error.localizedDescription } }
    }
    func loadProfile() async {
        let account = api.session?.user.id
        do {
            let value: Profile? = try await api.request("/v1/profile",authenticated:true)
            if api.session?.user.id == account { profile = value }
        }
        catch { message = error.localizedDescription }
    }
    func requireAccount() -> Bool {
        if api.session == nil { loginPresented = true; return false }
        return library != nil
    }
    func set(_ media: Media, field: String, value: JSONValue, runtime: Int? = nil) {
        setMany(media,changes:[(field,value)],runtime:runtime)
    }
    func setMany(_ media: Media, changes: [(String,JSONValue)], runtime: Int? = nil) {
        guard requireAccount(), let library else { return }
        do {
            var saved = media.savedValue
            if case .object(var object) = saved {
                if let minutes = runtime ?? library.value(media.key,"media")?["runtime"]?.int { object["runtime"] = .number(Double(minutes)) }
                saved = .object(object)
            }
            let metadata: [(String,JSONValue)] = library.value(media.key,"media") != saved ? [("media",saved)] : []
            try library.setMany(mediaKey:media.key,changes:metadata + changes); sync()
        } catch { message = "Impossible d’enregistrer cette modification sur l’appareil." }
    }
    func sync() {
        guard syncTask == nil, let library, api.session?.user.id == library.accountID, !offline else { return }
        syncing = true
        let generation = syncGeneration
        syncTask = Task { [weak self, library] in
            guard let self else { return }
            defer { if generation == syncGeneration { syncing = false; syncTask = nil } }
            do {
                var offset = 0
                while true {
                    try Task.checkCancellation()
                    let page: [LibraryField] = try await api.request("/v1/library",query:[URLQueryItem(name:"offset",value:String(offset))],authenticated:true)
                    try Task.checkCancellation()
                    try library.merge(page)
                    if page.count < 500 { break }; offset += page.count
                }
                var conflicts = 0
                while let mutation = try library.prepareNextMutation() {
                    try Task.checkCancellation()
                    guard api.session?.user.id == library.accountID else { return }
                    let result: MutationResult = try await api.request("/v1/library/mutations",method:"POST",body:mutation)
                    try Task.checkCancellation()
                    if let record = result.record {
                        if result.conflict { try library.rebase(mutation.mutationID,record:record); conflicts += 1 }
                        else { try library.acknowledge(mutation.mutationID,record:record); conflicts = 0 }
                    } else { throw UserFacingError(message:"La synchronisation n’a pas abouti.") }
                    if conflicts > 3 { throw UserFacingError(message:"Ta collection est modifiée sur un autre appareil. Réessaie dans un instant.") }
                }
            } catch is CancellationError {} catch { if !offline { message = error.localizedDescription } }
        }
    }
    func signOut() async {
        let currentLibrary = library
        do {
            syncTask?.cancel()
            try await api.signOut()
            try currentLibrary?.erase(); changeAccount()
        } catch { message = error.localizedDescription }
    }
    func deleteAccount() async {
        struct Confirmation: Encodable { let confirmation = "SUPPRIMER" }
        let currentLibrary = library
        do {
            syncTask?.cancel()
            let _: Empty = try await api.request("/v1/account",method:"DELETE",body:Confirmation())
            try api.clearSession(); changeAccount(); try currentLibrary?.erase()
        } catch { message = error.localizedDescription }
    }
}
