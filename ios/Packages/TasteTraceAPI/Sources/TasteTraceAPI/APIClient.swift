import Foundation

/// Thin JSON client for the TasteTrace API. Endpoint methods live in
/// extensions under Endpoints/.
public final class APIClient: Sendable {
    public let baseURL: URL
    let transport: Transport
    let tokenProvider: TokenProvider

    public init(baseURL: URL, transport: Transport = URLSessionTransport(), tokenProvider: TokenProvider = StaticTokenProvider(nil)) {
        self.baseURL = baseURL
        self.transport = transport
        self.tokenProvider = tokenProvider
    }

    public enum Method: String { case get = "GET", post = "POST", put = "PUT", patch = "PATCH", delete = "DELETE" }

    /// Sends form-encoded fields. Only sign-in needs this: the API follows the
    /// OAuth2 password-flow convention there, and JSON everywhere else.
    public func requestForm<T: Decodable>(_ path: String, fields: [String: String]) async throws -> T {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = Method.post.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(Self.formEncode(fields).utf8)

        let (data, response) = try await transport.send(request)
        guard (200...299).contains(response.statusCode) else {
            throw Self.error(for: response.statusCode, data: data)
        }
        do {
            return try JSONCoding.decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding("\(T.self): \(error)")
        }
    }

    static func formEncode(_ fields: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return fields
            .map { key, value in
                let name = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
                let encoded = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
                return "\(name)=\(encoded)"
            }
            .joined(separator: "&")
    }

    static func error(for status: Int, data: Data) -> APIError {
        if status == 401 { return .unauthorized }
        let message = try? JSONCoding.decoder.decode(ServerErrorBody.self, from: data).message
        return .server(status: status, message: message)
    }

    /// Sends a request and decodes the JSON body into `T`.
    public func request<T: Decodable>(_ method: Method, _ path: String, query: [String: String?] = [:], body: (some Encodable)? = Optional<EmptyBody>.none) async throws -> T {
        let data = try await send(method, path, query: query, body: body)
        do {
            return try JSONCoding.decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding("\(T.self): \(error)")
        }
    }

    /// Sends a request whose response body is ignored (204s, plain-text 200s).
    public func requestVoid(_ method: Method, _ path: String, query: [String: String?] = [:], body: (some Encodable)? = Optional<EmptyBody>.none) async throws {
        _ = try await send(method, path, query: query, body: body)
    }

    /// Sends a request and returns the raw body (CSV downloads).
    public func requestData(_ method: Method, _ path: String, query: [String: String?] = [:]) async throws -> Data {
        try await send(method, path, query: query, body: Optional<EmptyBody>.none)
    }

    private func send(_ method: Method, _ path: String, query: [String: String?], body: (some Encodable)?) async throws -> Data {
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        let items = query.compactMap { key, value in value.map { URLQueryItem(name: key, value: $0) } }
        if !items.isEmpty { components.queryItems = items }

        var request = URLRequest(url: components.url!)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = try JSONCoding.encoder.encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let token = await tokenProvider.currentToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await transport.send(request)
        guard (200...299).contains(response.statusCode) else {
            throw Self.error(for: response.statusCode, data: data)
        }
        return data
    }
}

public struct EmptyBody: Encodable {}
