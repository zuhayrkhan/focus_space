import Foundation

enum FocusMapLoadSource: Equatable, Sendable {
    case none
    case primary
    case recovery
}

struct FocusMapLoadOutcome: Equatable, Sendable {
    let map: FocusMap?
    let source: FocusMapLoadSource
}

struct FocusMapStorageLocations: Equatable, Sendable {
    let primary: URL?
    let recovery: URL?

    static let unavailable = Self(primary: nil, recovery: nil)
}

protocol FocusMapRepository: Sendable {
    var storageLocations: FocusMapStorageLocations { get }
    func load() throws -> FocusMap?
    func loadRecovering() throws -> FocusMapLoadOutcome
    func save(_ map: FocusMap) throws
}

extension FocusMapRepository {
    var storageLocations: FocusMapStorageLocations { .unavailable }

    func loadRecovering() throws -> FocusMapLoadOutcome {
        let map = try load()
        return FocusMapLoadOutcome(map: map, source: map == nil ? .none : .primary)
    }
}

enum FocusMapPersistenceError: LocalizedError {
    case primaryAndRecoveryUnreadable

    var errorDescription: String? {
        switch self {
        case .primaryAndRecoveryUnreadable:
            "Neither the saved space nor its recovery copy could be opened."
        }
    }
}

enum FocusMapJSONCodec {
    static func encode(_ map: FocusMap) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(map)
    }

    static func decode(_ data: Data) throws -> FocusMap {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(FocusMap.self, from: data)
    }
}

struct JSONFocusMapRepository: FocusMapRepository {
    let fileURL: URL

    var recoveryURL: URL {
        fileURL.deletingPathExtension().appendingPathExtension("recovery.json")
    }

    var storageLocations: FocusMapStorageLocations {
        FocusMapStorageLocations(primary: fileURL, recovery: recoveryURL)
    }

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    init(fileManager: FileManager = .default) {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        fileURL = support
            .appending(path: "Focus Space", directoryHint: .isDirectory)
            .appending(path: "focus-space.json")
    }

    func load() throws -> FocusMap? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return try FocusMapJSONCodec.decode(Data(contentsOf: fileURL))
    }

    func loadRecovering() throws -> FocusMapLoadOutcome {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            if FileManager.default.fileExists(atPath: recoveryURL.path),
               let recovered = try? FocusMapJSONCodec.decode(Data(contentsOf: recoveryURL)) {
                return FocusMapLoadOutcome(map: recovered, source: .recovery)
            }
            return FocusMapLoadOutcome(map: nil, source: .none)
        }
        do {
            return FocusMapLoadOutcome(map: try load(), source: .primary)
        } catch {
            guard FileManager.default.fileExists(atPath: recoveryURL.path),
                  let recovered = try? FocusMapJSONCodec.decode(Data(contentsOf: recoveryURL)) else {
                throw FocusMapPersistenceError.primaryAndRecoveryUnreadable
            }
            return FocusMapLoadOutcome(map: recovered, source: .recovery)
        }
    }

    func save(_ map: FocusMap) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if fileManager.fileExists(atPath: fileURL.path) {
            let existing = try Data(contentsOf: fileURL)
            if (try? FocusMapJSONCodec.decode(existing)) != nil {
                try existing.write(to: recoveryURL, options: .atomic)
            }
        }

        try FocusMapJSONCodec.encode(map).write(to: fileURL, options: .atomic)
    }
}
