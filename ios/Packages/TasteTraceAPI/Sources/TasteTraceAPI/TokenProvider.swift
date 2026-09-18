import Foundation

/// Supplies the bearer token for authenticated requests.
public protocol TokenProvider: Sendable {
    func currentToken() async -> String?
}

public struct StaticTokenProvider: TokenProvider {
    let token: String?
    public init(_ token: String?) { self.token = token }
    public func currentToken() async -> String? { token }
}
