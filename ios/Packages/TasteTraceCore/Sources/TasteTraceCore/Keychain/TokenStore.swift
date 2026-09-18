import Foundation

/// Where the device token lives between launches.
public protocol TokenStore: Sendable {
    func load() -> String?
    func save(_ token: String) throws
    func clear()
}

public final class InMemoryTokenStore: TokenStore, @unchecked Sendable {
    private var token: String?
    public init(_ token: String? = nil) { self.token = token }
    public func load() -> String? { token }
    public func save(_ token: String) throws { self.token = token }
    public func clear() { token = nil }
}
