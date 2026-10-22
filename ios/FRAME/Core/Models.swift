import Foundation

enum JSONValue: Codable, Equatable {
    case null, bool(Bool), number(Double), string(String), object([String: JSONValue]), array([JSONValue])
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([String: JSONValue].self) { self = .object(v) }
        else { self = .array(try c.decode([JSONValue].self)) }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        }
    }
    var bool: Bool { if case .bool(let b) = self { return b }; return false }
    var int: Int? { if case .number(let n) = self, n.isFinite, abs(n) < 1_000_000_000 { return Int(n) }; return nil }
    var string: String? { if case .string(let s) = self { return s }; return nil }
    subscript(_ key: String) -> JSONValue? { if case .object(let o) = self { return o[key] }; return nil }
}

struct Media: Codable, Identifiable, Hashable {
    let id: Int
    let key: String
    let type: String
    let category: String
    let title: String
    let year: String
    let overview: String
    let poster: String?
    let backdrop: String?
    let rating: String?
    var posterURL: URL? { Self.artURL(poster) }
    var backdropURL: URL? { Self.artURL(backdrop) }
    static func artURL(_ value: String?) -> URL? {
        guard let value, let url = URL(string: value), url.scheme == "https", url.host == "image.tmdb.org" else { return nil }
        return url
    }
    var savedValue: JSONValue {
        .object(["id": .number(Double(id)), "key": .string(key), "type": .string(type),
                 "category": .string(category), "title": .string(title), "year": .string(year),
                 "overview": .string(String(overview.prefix(3000))), "poster": poster.map(JSONValue.string) ?? .null,
                 "backdrop": backdrop.map(JSONValue.string) ?? .null, "rating": rating.map(JSONValue.string) ?? .null])
    }
    static func saved(_ value: JSONValue?) -> Media? {
        guard let value, let data = try? JSONEncoder().encode(value) else { return nil }
        return try? JSONDecoder().decode(Media.self, from: data)
    }
}
struct HomePayload: Decodable { let lead: Media?; let films: [Media]; let shows: [Media]; let animes: [Media] }
struct MediaPage: Decodable { let items: [Media]; let page: Int; let totalPages: Int }
struct MediaDetail: Decodable {
    let id: Int; let title: String; let overview: String; let genres: [String]; let runtime: Int?
    let seasons: [SeasonSummary]; let nextEpisode: NextEpisode?; let videos: [Trailer]; let homepage: String?
}
struct SeasonSummary: Decodable, Identifiable { let number: Int; let name: String; let count: Int; var id: Int { number } }
struct NextEpisode: Decodable { let name: String?; let airDate: String?; let season: Int; let episode: Int }
struct Trailer: Decodable, Identifiable { let id: String; let name: String }
struct SeasonPayload: Decodable { let number: Int; let name: String; let episodes: [Episode] }
struct Episode: Decodable, Identifiable {
    let id: Int; let season: Int; let number: Int; let name: String; let description: String; let airDate: String?; let runtime: Int?; let still: String?
    var field: String { "episode:\(season):\(number)" }
    var hasAired: Bool {
        guard let airDate, !airDate.isEmpty else { return false }
        return airDate <= Self.today
    }
    static var today: String { let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f.string(from: Date()) }
}
struct EarlierEpisodes: Decodable { let episodes: [EarlierEpisode] }
struct EarlierEpisode: Decodable { let season: Int; let number: Int; let runtime: Int? }

struct LibraryField: Codable, Equatable {
    let mediaKey: String; let field: String; let value: JSONValue; let revision: Int
    enum CodingKeys: String, CodingKey { case mediaKey = "media_key", field, value, revision }
    init(mediaKey: String, field: String, value: JSONValue, revision: Int) { self.mediaKey = mediaKey; self.field = field; self.value = value; self.revision = revision }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mediaKey = try c.decode(String.self, forKey: .mediaKey); field = try c.decode(String.self, forKey: .field)
        value = try c.decodeIfPresent(JSONValue.self, forKey: .value) ?? .null; revision = try c.decode(Int.self, forKey: .revision)
    }
    var identity: String { mediaKey + "/" + field }
}
struct LibraryMutation: Codable, Equatable, Identifiable {
    let mutationID: UUID; let mediaKey: String; let field: String; let value: JSONValue; var expectedRevision: Int
    var id: UUID { mutationID }
    enum CodingKeys: String, CodingKey { case mutationID = "mutation_id", mediaKey = "media_key", field, value, expectedRevision = "expected_revision" }
}
struct MutationResult: Decodable { let conflict: Bool; let record: LibraryField? }
struct PublicConfig: Codable {
    let supabaseURL: URL; let supabaseKey: String; let communityEnabled: Bool
    let termsURL: URL; let privacyURL: URL; let supportURL: URL; let termsVersion: String
}
struct AuthUser: Codable { let id: UUID; let email: String? }
struct AuthSession: Codable {
    let accessToken: String; let refreshToken: String; let expiresAt: TimeInterval; let user: AuthUser
    enum CodingKeys: String, CodingKey { case accessToken = "access_token", refreshToken = "refresh_token", expiresAt = "expires_at", expiresIn = "expires_in", user }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        accessToken = try c.decode(String.self, forKey: .accessToken); refreshToken = try c.decode(String.self, forKey: .refreshToken)
        user = try c.decode(AuthUser.self, forKey: .user)
        if let date = try c.decodeIfPresent(Double.self, forKey: .expiresAt) { expiresAt = date }
        else { expiresAt = Date().timeIntervalSince1970 + (try c.decode(Double.self, forKey: .expiresIn)) }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(accessToken, forKey: .accessToken); try c.encode(refreshToken, forKey: .refreshToken)
        try c.encode(expiresAt, forKey: .expiresAt); try c.encode(user, forKey: .user)
    }
}
struct Profile: Codable {
    let id: UUID; var nickname: String; var bio: String; var avatar: String; let acceptedTermsVersion: String?
    enum CodingKeys: String, CodingKey { case id, nickname, bio, avatar, acceptedTermsVersion = "accepted_terms_version" }
}
struct CommunityPost: Decodable, Identifiable {
    let id: UUID; let authorID: UUID; let mediaKey: String; let content: String; let rating: Int?
    let createdAt: String; let nickname: String; let avatar: String
    enum CodingKeys: String, CodingKey { case id, authorID = "author_id", mediaKey = "media_key", content, rating, createdAt = "created_at", nickname, avatar }
}
struct BlockedUser: Decodable, Identifiable { let blockedID: UUID; var id: UUID { blockedID }; enum CodingKeys: String,CodingKey { case blockedID = "blocked_id" } }
struct Empty: Decodable {}

struct UserFacingError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
