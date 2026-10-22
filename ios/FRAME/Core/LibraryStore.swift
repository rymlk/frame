import Foundation
import Combine

@MainActor
final class LibraryStore: ObservableObject {
    let accountID: UUID
    private let file: URL
    @Published private(set) var records: [String: LibraryField] = [:]
    @Published private(set) var pending: [LibraryMutation] = []
    private struct Snapshot: Codable { let records: [String: LibraryField]; let pending: [LibraryMutation] }

    init(directory: URL, accountID: UUID) throws {
        self.accountID = accountID
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        file = directory.appendingPathComponent(accountID.uuidString + ".json")
        if FileManager.default.fileExists(atPath: file.path) {
            let saved = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: file))
            records = saved.records; pending = saved.pending
        }
    }
    func value(_ mediaKey: String, _ field: String) -> JSONValue? {
        pending.last(where: { $0.mediaKey == mediaKey && $0.field == field })?.value ?? records[mediaKey + "/" + field]?.value
    }
    func set(mediaKey: String, field: String, value: JSONValue) throws {
        try setMany(mediaKey:mediaKey,changes:[(field,value)])
    }
    func setMany(mediaKey: String, changes: [(String,JSONValue)]) throws {
        var queue = pending
        queue += changes.map { LibraryMutation(mutationID:UUID(),mediaKey:mediaKey,field:$0.0,value:$0.1,expectedRevision:-1) }
        try save(records: records, pending: queue)
    }
    func merge(_ changes: [LibraryField]) throws {
        var next = records
        for record in changes where record.revision >= (next[record.identity]?.revision ?? 0) { next[record.identity] = record }
        try save(records: next, pending: pending)
    }
    func acknowledge(_ id: UUID, record: LibraryField) throws {
        var next = records
        if record.revision >= (next[record.identity]?.revision ?? 0) { next[record.identity] = record }
        try save(records: next, pending: pending.filter { $0.id != id })
    }
    func nextMutation() -> LibraryMutation? {
        guard var first = pending.first else { return nil }
        if first.expectedRevision < 0 { first.expectedRevision = records[first.mediaKey + "/" + first.field]?.revision ?? 0 }
        return first
    }
    // Freeze the request on disk before sending. A lost HTTP response must replay
    // the identical payload even after another pull or an application restart.
    func prepareNextMutation() throws -> LibraryMutation? {
        guard let next = nextMutation() else { return nil }
        if pending.first?.expectedRevision == -1 {
            var queue = pending; queue[0] = next
            try save(records:records,pending:queue)
        }
        return next
    }
    func rebase(_ id: UUID, record: LibraryField) throws {
        var next = records; var queue = pending
        if record.revision >= (next[record.identity]?.revision ?? 0) { next[record.identity] = record }
        if let index = queue.firstIndex(where: { $0.id == id }) { queue[index].expectedRevision = record.revision }
        try save(records:next,pending:queue)
    }
    var mediaKeys: [String] { Array(Set(records.values.map(\.mediaKey) + pending.map(\.mediaKey))).sorted() }
    var savedMedia: [Media] {
        mediaKeys.compactMap { key in
            let active = value(key,"watchlist")?.bool == true || value(key,"watched")?.bool == true || value(key,"rating")?.int != nil || !(value(key,"review")?.string ?? "").isEmpty || hasWatchedEpisodes(key)
            return active ? Media.saved(value(key,"media")) : nil
        }.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }
    func hasWatchedEpisodes(_ key: String) -> Bool { episodeFields(key).contains { value(key,$0)?["watched"]?.bool == true } }
    func episodeFields(_ key: String) -> [String] {
        Set(records.values.filter { $0.mediaKey == key && $0.field.hasPrefix("episode:") }.map(\.field) + pending.filter { $0.mediaKey == key && $0.field.hasPrefix("episode:") }.map(\.field)).sorted()
    }
    var watchedEpisodes: Int { mediaKeys.reduce(0) { n,key in n + episodeFields(key).filter { value(key,$0)?["watched"]?.bool == true }.count } }
    var watchMinutes: Int {
        mediaKeys.reduce(0) { total,key in total + episodeFields(key).reduce(0) { n,f in
            n + (value(key,f)?["watched"]?.bool == true ? (value(key,f)?["runtime"]?.int ?? 0) : 0)
        } + (value(key,"watched")?.bool == true ? (value(key,"media")?["runtime"]?.int ?? 0) : 0) }
    }
    func erase() throws {
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
        records = [:]; pending = []
    }
    private func save(records next: [String: LibraryField], pending queue: [LibraryMutation]) throws {
        let data = try JSONEncoder().encode(Snapshot(records: next, pending: queue))
        try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        records = next; pending = queue
    }
}
