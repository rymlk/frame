import XCTest
@testable import FRAME

final class StubURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status,data) = try Self.handler!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type":"application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

@MainActor
final class NetworkingTests: XCTestCase {
    func testAnonymousBrowseDoesNotSendSessionAndAPIErrorIsReadable() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let api = FrameAPI(baseURL: URL(string: "https://frame.test")!, session: URLSession(configuration: config))
        StubURLProtocol.handler = { request in
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            XCTAssertEqual(request.url?.query, "type=movie")
            return (503,Data(#"{"error":"Catalogue temporairement indisponible."}"#.utf8))
        }
        defer { StubURLProtocol.handler = nil }
        do {
            let _: MediaPage = try await api.request("/api/discover", query: [URLQueryItem(name: "type",value: "movie")])
            XCTFail("Expected service error")
        } catch {
            XCTAssertEqual(error.localizedDescription,"Catalogue temporairement indisponible.")
        }
    }

    func testPrivateRequestWithoutSessionFailsBeforeSendingAnything() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let api = FrameAPI(baseURL: URL(string: "https://frame-no-session.test")!, session: URLSession(configuration: config))
        StubURLProtocol.handler = { _ in XCTFail("Must not send private request"); return (200,Data()) }
        defer { StubURLProtocol.handler = nil }
        do {
            let _: [LibraryField] = try await api.request("/v1/library", authenticated: true)
            XCTFail("Expected authentication error")
        } catch { XCTAssertEqual(error.localizedDescription,"Connecte-toi pour continuer.") }
    }

    func testSignOutAlwaysClearsLocalCredentialsWhenNetworkFails() async throws {
        let host = UUID().uuidString.lowercased() + ".test"
        let vault = SessionVault(service:"com.frame.auth." + host)
        let data = Data(#"{"access_token":"a","refresh_token":"r","expires_at":9999999999,"user":{"id":"11111111-1111-4111-8111-111111111111"}}"#.utf8)
        try vault.save(JSONDecoder().decode(AuthSession.self,from:data))
        defer { try? vault.delete(); StubURLProtocol.handler = nil }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        StubURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        let api = FrameAPI(baseURL:URL(string:"https://" + host)!,session:URLSession(configuration:config))
        XCTAssertNotNil(api.session)
        try await api.signOut()
        XCTAssertNil(api.session)
        XCTAssertNil(try vault.load())
    }

    func testRevokedRefreshTokenAllowsSigningInAgain() async throws {
        let host = UUID().uuidString.lowercased() + ".test"
        let vault = SessionVault(service:"com.frame.auth." + host)
        let data = Data(#"{"access_token":"expired","refresh_token":"revoked","expires_at":0,"user":{"id":"11111111-1111-4111-8111-111111111111"}}"#.utf8)
        try vault.save(JSONDecoder().decode(AuthSession.self,from:data))
        defer { try? vault.delete(); StubURLProtocol.handler = nil; UserDefaults.standard.removeObject(forKey:"frame.publicConfig.https://" + host) }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        StubURLProtocol.handler = { request in
            if request.url?.path == "/v1/config" {
                return (200,Data(#"{"supabaseURL":"https://auth.test","supabaseKey":"public","communityEnabled":false,"termsURL":"https://frame.test/terms","privacyURL":"https://frame.test/privacy","supportURL":"https://frame.test/support","termsVersion":"2026-10-22"}"#.utf8))
            }
            XCTAssertEqual(request.url?.query,"grant_type=refresh_token")
            return (400,Data(#"{"error":"invalid_grant"}"#.utf8))
        }
        let api = FrameAPI(baseURL:URL(string:"https://" + host)!,session:URLSession(configuration:config))
        do { _ = try await api.accessToken(); XCTFail("Expected revoked session to fail") }
        catch { XCTAssertTrue(error.localizedDescription.contains("Reconnecte-toi")) }
        XCTAssertNil(api.session)
        XCTAssertNil(try vault.load())
    }
}
