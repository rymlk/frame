import XCTest
@testable import FRAME

@MainActor
final class LibraryTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testOfflineChangesSurviveRestartAndNeverLeakAcrossAccounts() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let account = UUID()
        let store = try LibraryStore(directory: dir, accountID: account)
        try store.set(mediaKey: "tv:42", field: "watchlist", value: .bool(true))
        let reloaded = try LibraryStore(directory: dir, accountID: account)
        XCTAssertEqual(reloaded.value("tv:42", "watchlist"), .bool(true))
        XCTAssertEqual(reloaded.pending.count, 1)
        let other = try LibraryStore(directory: dir, accountID: UUID())
        XCTAssertNil(other.value("tv:42", "watchlist"))
        XCTAssertTrue(other.pending.isEmpty)
    }

    func testConflictRebasesWithoutLosingNewerLocalChange() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try LibraryStore(directory: dir, accountID: UUID())
        try store.set(mediaKey: "movie:1", field: "watched", value: .bool(true))
        let first = try XCTUnwrap(store.nextMutation())
        try store.set(mediaKey: "movie:1", field: "watched", value: .bool(false))
        try store.merge([LibraryField(mediaKey: "movie:1", field: "watched", value: .bool(false), revision: 4)])
        XCTAssertEqual(store.nextMutation()?.expectedRevision, 4)
        XCTAssertEqual(store.nextMutation()?.mutationID, first.mutationID)
        XCTAssertEqual(store.value("movie:1", "watched"), .bool(false))
        try store.acknowledge(first.mutationID, record: LibraryField(mediaKey: "movie:1", field: "watched", value: .bool(true), revision: 5))
        XCTAssertEqual(store.pending.count, 1)
        XCTAssertEqual(store.value("movie:1", "watched"), .bool(false))
        XCTAssertEqual(store.nextMutation()?.expectedRevision, 5)
    }

    func testTombstoneAndIdempotentAcknowledgement() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try LibraryStore(directory: dir, accountID: UUID())
        try store.merge([LibraryField(mediaKey: "tv:1", field: "rating", value: .number(4), revision: 2)])
        try store.set(mediaKey: "tv:1", field: "rating", value: .null)
        XCTAssertEqual(store.value("tv:1", "rating"), .null)
        let mutation = try XCTUnwrap(store.nextMutation())
        let record = LibraryField(mediaKey: "tv:1", field: "rating", value: .null, revision: 3)
        try store.acknowledge(mutation.mutationID, record: record)
        try store.acknowledge(mutation.mutationID, record: record)
        XCTAssertTrue(store.pending.isEmpty)
        let loaded = try LibraryStore(directory: dir, accountID: store.accountID)
        XCTAssertEqual(loaded.value("tv:1", "rating"), .null)
        try loaded.merge([LibraryField(mediaKey: "tv:1", field: "rating", value: .number(5), revision: 1)])
        XCTAssertEqual(loaded.value("tv:1", "rating"), .null)
    }

    func testMutationWireFormatAndSessionDecoding() throws {
        let mutation = LibraryMutation(mutationID: UUID(), mediaKey: "tv:1", field: "watchlist", value: .bool(true), expectedRevision: 0)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(mutation)) as? [String: Any])
        XCTAssertNotNil(json["mutation_id"])
        XCTAssertEqual(json["media_key"] as? String, "tv:1")
        XCTAssertEqual(json["expected_revision"] as? Int, 0)
        let data = Data(#"{"access_token":"a","refresh_token":"r","expires_in":3600,"user":{"id":"11111111-1111-4111-8111-111111111111","email":"a@example.com"}}"#.utf8)
        let session = try JSONDecoder().decode(AuthSession.self, from: data)
        XCTAssertEqual(session.refreshToken, "r")
        XCTAssertGreaterThan(session.expiresAt, Date().timeIntervalSince1970 + 3500)
    }

    func testLostResponseRetriesExactlyTheSameMutationAfterRestartAndPull() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let account = UUID()
        let store = try LibraryStore(directory: dir, accountID: account)
        try store.set(mediaKey: "movie:1", field: "watchlist", value: .bool(true))
        let sent = try XCTUnwrap(store.prepareNextMutation())
        XCTAssertEqual(sent.expectedRevision, 0)
        let restart = try LibraryStore(directory: dir, accountID: account)
        try restart.merge([LibraryField(mediaKey: "movie:1", field: "watchlist", value: .bool(true), revision: 1)])
        XCTAssertEqual(try restart.prepareNextMutation(), sent)
        try restart.rebase(sent.mutationID, record: LibraryField(mediaKey: "movie:1", field: "watchlist", value: .bool(false), revision: 2))
        XCTAssertEqual(try restart.prepareNextMutation()?.expectedRevision, 2)
        XCTAssertEqual(restart.value("movie:1", "watchlist"), .bool(true))
    }

    func testBatchEpisodeProgressPersistsInOrder() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let account = UUID()
        let store = try LibraryStore(directory:dir,accountID:account)
        let changes: [(String,JSONValue)] = (1...100).map { ("episode:1:\($0)",.object(["watched":.bool(true),"runtime":.number(24)])) }
        try store.setMany(mediaKey:"tv:1",changes:changes)
        let restarted = try LibraryStore(directory:dir,accountID:account)
        XCTAssertEqual(restarted.pending.count,100)
        XCTAssertEqual(restarted.watchedEpisodes,100)
        XCTAssertEqual(restarted.watchMinutes,2400)
        XCTAssertEqual(restarted.pending.last?.field,"episode:1:100")
    }
}
