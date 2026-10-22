import Foundation
import Combine

@MainActor
final class FrameAPI: ObservableObject {
    let baseURL: URL?
    private let http: URLSession
    private let vault: SessionVault
    private var refreshTask: Task<AuthSession, Error>?
    @Published private(set) var config: PublicConfig?
    @Published private(set) var session: AuthSession?
    @Published private(set) var restorationError: String?
    private var configCacheKey: String { "frame.publicConfig." + (baseURL?.absoluteString ?? "unconfigured") }

    init(baseURL: URL?, session http: URLSession = .shared) {
        self.baseURL = baseURL; self.http = http
        vault = SessionVault(service: "com.frame.auth." + (baseURL?.host ?? "unconfigured"))
        do { self.session = try vault.load() } catch { restorationError = error.localizedDescription }
        if let data = UserDefaults.standard.data(forKey: configCacheKey), let saved = try? JSONDecoder().decode(PublicConfig.self,from:data), Self.valid(saved) { config = saved }
    }
    static func valid(_ config: PublicConfig) -> Bool {
        let urls: [URL] = [config.supabaseURL,config.termsURL,config.privacyURL,config.supportURL]
        for url in urls {
            guard url.scheme == "https", url.host != nil, url.user == nil, url.password == nil else { return false }
        }
        return !config.supabaseKey.isEmpty
    }
    func loadConfig() async throws {
        let value: PublicConfig = try await request("/v1/config")
        guard Self.valid(value) else { throw UserFacingError(message:"Le service est temporairement indisponible.") }
        UserDefaults.standard.set(try JSONEncoder().encode(value),forKey:configCacheKey); config = value
    }
    func request<T: Decodable>(_ path: String, method: String = "GET", query: [URLQueryItem] = [], body: Data? = nil, authenticated: Bool = false) async throws -> T {
        guard let baseURL, baseURL.scheme == "https" else { throw UserFacingError(message:"FRAME n’est pas encore connecté à son service en ligne.") }
        var components = URLComponents(url:baseURL.appendingPathComponent(path),resolvingAgainstBaseURL:false)!
        components.queryItems = query.isEmpty ? nil : query
        let token = authenticated ? try await accessToken() : nil
        return try await send(url:components.url!,method:method,body:body,token:token)
    }
    func request<T: Decodable, B: Encodable>(_ path: String, method: String, body: B, authenticated: Bool = true) async throws -> T {
        try await request(path,method:method,body:JSONEncoder().encode(body),authenticated:authenticated)
    }
    private func send<T: Decodable>(url: URL, method: String, body: Data?, token: String?, apiKey: String? = nil) async throws -> T {
        var request = URLRequest(url:url); request.httpMethod = method; request.httpBody = body; request.timeoutInterval = 20
        request.setValue("application/json",forHTTPHeaderField:"Accept")
        if body != nil { request.setValue("application/json",forHTTPHeaderField:"Content-Type") }
        if let token { request.setValue("Bearer " + token,forHTTPHeaderField:"Authorization") }
        if let apiKey { request.setValue(apiKey,forHTTPHeaderField:"apikey") }
        let (data,response) = try await http.data(for:request)
        guard let response = response as? HTTPURLResponse else { throw UserFacingError(message:"Réponse du service invalide.") }
        guard (200..<300).contains(response.statusCode) else {
            let payload = try? JSONSerialization.jsonObject(with:data) as? [String:Any]
            let message = payload?["error"] as? String
            if response.statusCode == 401 { throw UserFacingError(message:"Ta session a expiré. Reconnecte-toi.") }
            if response.statusCode == 429 { throw UserFacingError(message:"Trop de demandes. Attends un instant avant de réessayer.") }
            throw UserFacingError(message:message ?? "La demande n’a pas abouti. Réessaie dans un instant.")
        }
        return try JSONDecoder().decode(T.self,from:data.isEmpty ? Data("{}".utf8) : data)
    }
    private func auth<T: Decodable>(_ path: String, body: [String:String], token: String? = nil) async throws -> T {
        if config == nil { try await loadConfig() }
        guard let config else { throw UserFacingError(message:"Connexion indisponible.") }
        // path can contain the refresh grant query; it is constructed internally.
        let url = URL(string:config.supabaseURL.absoluteString + "/auth/v1/" + path)!
        return try await send(url:url,method:"POST",body:JSONEncoder().encode(body),token:token,apiKey:config.supabaseKey)
    }
    func sendCode(email: String) async throws {
        if config == nil { try await loadConfig() }
        guard let config else { throw UserFacingError(message:"Connexion indisponible.") }
        struct OTP: Encodable { let email: String; let create_user = true }
        let _: Empty = try await send(url:config.supabaseURL.appendingPathComponent("auth/v1/otp"),method:"POST",body:JSONEncoder().encode(OTP(email:email)),token:nil,apiKey:config.supabaseKey)
    }
    func verifyCode(email: String, code: String) async throws {
        let value: AuthSession = try await auth("verify",body:["email":email,"token":code,"type":"email"])
        try vault.save(value); session = value
    }
    func accessToken() async throws -> String {
        guard let current = session else { throw UserFacingError(message:"Connecte-toi pour continuer.") }
        if current.expiresAt > Date().timeIntervalSince1970 + 60 { return current.accessToken }
        if let refreshTask { return try await refreshTask.value.accessToken }
        let task = Task<AuthSession, Error> { [self] in
            let value: AuthSession = try await auth("token?grant_type=refresh_token",body:["refresh_token":current.refreshToken])
            try vault.save(value); session = value; return value
        }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value.accessToken
    }
    func signOut() async throws {
        let token = try await accessToken()
        let _: Empty = try await auth("logout?scope=local",body:[:],token:token)
        try clearSession()
    }
    func clearSession() throws { refreshTask?.cancel(); refreshTask = nil; try vault.delete(); session = nil }
}
