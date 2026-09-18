import Foundation
import TasteTraceAPI

/// Small on-disk cache: one Codable value per file under Application Support.
/// Used for offline reads; the API stays the source of truth.
public struct JSONFileStore<Value: Codable>: Sendable {
    public let url: URL

    public init(name: String, directory: URL = JSONFileStore.defaultDirectory) {
        url = directory.appending(path: "\(name).json")
    }

    public static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        return base.appending(path: "TasteTrace", directoryHint: .isDirectory)
    }

    public func load() -> Value? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONCoding.decoder.decode(Value.self, from: data)
    }

    public func save(_ value: Value) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONCoding.encoder.encode(value).write(to: url, options: .atomic)
    }

    public func clear() {
        try? FileManager.default.removeItem(at: url)
    }

    /// Removes every cached file (Profile → "Clear Local Journal History").
    public static func clearAll(directory: URL = defaultDirectory) {
        try? FileManager.default.removeItem(at: directory)
    }
}
