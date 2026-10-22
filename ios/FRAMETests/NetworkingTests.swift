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
}
