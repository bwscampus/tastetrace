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

/// Shape of the error bodies the backend sends.
///
/// FastAPI puts the text in `detail`, which is what this app talks to now. The
/// `message` key is what the old Express backend sent; reading both means the
/// server's own wording reaches the screen either way. Before this handled
/// `detail`, every message the API sent was dropped and people saw only
/// "Request failed (503)".
///
/// A 422 is the deliberate exception: FastAPI makes `detail` an array of field
/// errors there, which has no single sentence worth showing, so decoding fails
/// and the caller falls back to the generic text.
struct ServerErrorBody: Decodable {
    let message: String

    private enum CodingKeys: String, CodingKey {
        case detail
        case message
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let detail = try? container.decode(String.self, forKey: .detail) {
            message = detail
        } else {
            message = try container.decode(String.self, forKey: .message)
        }
    }
}
