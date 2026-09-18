import XCTest
@testable import TasteTraceFeatures
@testable import TasteTraceAPI
@testable import TasteTraceCore

final class AuthViewModelTests: XCTestCase {
    @MainActor
    func testSubmitGatingAndErrorMapping() async {
        let transport = StubTransport(status: 401, body: "Unauthorized")
        let session = AuthSession.make(baseURL: URL(string: "https://api.example")!, tokenStore: InMemoryTokenStore(), transport: transport)
        let model = AuthViewModel(session: session)

        XCTAssertFalse(model.canSubmit)
        model.email = "a@b.co"; model.password = "short"
        XCTAssertFalse(model.canSubmit)
        model.password = "longenough"
        XCTAssertTrue(model.canSubmit)

        await model.submit()
        XCTAssertEqual(model.error, "Incorrect email or password.")
        XCTAssertEqual(transport.requests.last?.url?.path, "/api/auth/token")
    }
}

final class StubTransport: Transport, @unchecked Sendable {
    let status: Int
    let body: String
    var requests: [URLRequest] = []
    init(status: Int, body: String) { self.status = status; self.body = body }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}
