import Foundation

public struct ArtifactManifestWriter {
    public enum Error: Swift.Error, LocalizedError {
        case encodingFailed(String)
        case writeFailed(URL, String)
    }

    public static let indexFileName = "index.json"

    public let encoder: JSONEncoder
    public let decoder: JSONDecoder
    public let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
        self.fileManager = fileManager
    }

    public func write(
        _ index: ArtifactIndex,
        to directory: URL,
        fileName: String = indexFileName
    ) throws -> URL {
        try createParentDirectoryIfNeeded(directory)
        let payload = try encode(index)
        let destination = directory.appendingPathComponent(fileName)
        do {
            try payload.write(to: destination, options: .atomic)
        } catch {
            throw Error.writeFailed(destination, "\(error)")
        }
        return destination
    }

    public func writeSummary(
        _ lines: [String],
        to directory: URL,
        fileName: String = "summary.txt"
    ) throws -> URL {
        try createParentDirectoryIfNeeded(directory)
        let destination = directory.appendingPathComponent(fileName)
        let content = lines.joined(separator: "\n")
        do {
            try content.write(to: destination, atomically: true, encoding: .utf8)
        } catch {
            throw Error.writeFailed(destination, "\(error)")
        }
        return destination
    }

    public func readIndex(from path: URL) throws -> ArtifactIndex {
        let data = try Data(contentsOf: path)
        do {
            return try decoder.decode(ArtifactIndex.self, from: data)
        } catch {
            throw Error.encodingFailed("\(error)")
        }
    }

    private func encode(_ index: ArtifactIndex) throws -> Data {
        do {
            return try encoder.encode(index)
        } catch {
            throw Error.encodingFailed("\(error)")
        }
    }

    private func createParentDirectoryIfNeeded(_ directory: URL) throws {
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }
    }
}
