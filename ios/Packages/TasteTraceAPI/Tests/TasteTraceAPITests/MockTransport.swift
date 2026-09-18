import Foundation
@testable import TasteTraceAPI

/// Serves canned responses per "METHOD path" and records the requests it saw.
final class MockTransport: Transport, @unchecked Sendable {
    struct Canned { let status: Int; let body: Data }
    var responses: [String: Canned] = [:]
    var requests: [URLRequest] = []

    func stub(_ method: String, _ path: String, status: Int = 200, json: String) {
        responses["\(method) \(path)"] = Canned(status: status, body: Data(json.utf8))
    }

    func stub(_ method: String, _ path: String, status: Int = 200, fixture: String) throws {
        let url = Bundle.module.url(forResource: fixture, withExtension: "json", subdirectory: "Fixtures")!
        responses["\(method) \(path)"] = Canned(status: status, body: try Data(contentsOf: url))
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let key = "\(request.httpMethod ?? "GET") \(request.url!.path)"
        guard let canned = responses[key] else {
            throw APIError.transport("No stub for \(key)")
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: canned.status, httpVersion: nil, headerFields: nil)!
        return (canned.body, response)
    }
}
