import Foundation

public struct DerivedDataManager {
    public let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func prepare(at path: URL) throws {
        if !fileManager.fileExists(atPath: path.path) {
            try fileManager.createDirectory(
                at: path,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }
    }
}
