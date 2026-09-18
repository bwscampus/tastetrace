import Foundation

public enum APIError: Error, Equatable, Sendable {
    /// 401 from the server: the token is missing, expired or revoked.
    case unauthorized
    /// Any other non-2xx response, with the server's `message` when it sent one.
    case server(status: Int, message: String?)
    /// The response body could not be decoded into the expected type.
    case decoding(String)
    /// No response at all (offline, DNS, timeout).
    case transport(String)

    public var message: String {
        switch self {
        case .unauthorized: return "Please sign in again."
        case let .server(status, message): return message ?? "Request failed (\(status))."
        case let .decoding(detail): return "Unexpected response: \(detail)"
        case let .transport(detail): return "Network error: \(detail)"
        }
    }
}

/// Shape of every error body the backend sends.
struct ServerErrorBody: Decodable {
    let message: String
}
