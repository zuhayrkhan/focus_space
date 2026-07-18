import Foundation

protocol FocusMapRepository: Sendable {
    func load() throws -> FocusMap?
    func save(_ map: FocusMap) throws
}

struct JSONFocusMapRepository: FocusMapRepository {
    let fileURL: URL

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
        return try JSONDecoder.focusSpace.decode(FocusMap.self, from: Data(contentsOf: fileURL))
    }

    func save(_ map: FocusMap) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder.focusSpace.encode(map)
        try data.write(to: fileURL, options: .atomic)
    }
}

private extension JSONEncoder {
    static var focusSpace: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var focusSpace: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
