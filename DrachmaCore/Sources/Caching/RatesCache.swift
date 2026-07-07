import Foundation

/// Last-good storage for rate snapshots — the offline-first half of the
/// manifesto. Actor-guarded; one JSON file per base currency, plus an
/// in-memory layer so repeat lookups never touch disk.
public actor RatesCache {
    private let directory: URL
    private var memory: [String: RatesSnapshot] = [:]

    /// Pass a directory in tests; defaults to the user caches directory.
    public init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DrachmaRates", isDirectory: true)
    }

    public func store(_ snapshot: RatesSnapshot) {
        let key = snapshot.base.uppercased()
        memory[key] = snapshot
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(to: fileURL(key: key), options: .atomic)
        }
    }

    public func snapshot(base: String) -> RatesSnapshot? {
        let key = base.uppercased()
        if let hit = memory[key] { return hit }
        guard let data = try? Data(contentsOf: fileURL(key: key)),
              let snapshot = try? JSONDecoder().decode(RatesSnapshot.self, from: data)
        else { return nil }
        memory[key] = snapshot
        return snapshot
    }

    private func fileURL(key: String) -> URL {
        directory.appendingPathComponent("\(key).json")
    }
}
