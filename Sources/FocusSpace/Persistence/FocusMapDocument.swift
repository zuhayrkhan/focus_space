import SwiftUI
import UniformTypeIdentifiers

struct FocusMapDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var map: FocusMap

    init(map: FocusMap) {
        self.map = map
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        map = try FocusMapJSONCodec.decode(data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try FocusMapJSONCodec.encode(map))
    }
}
