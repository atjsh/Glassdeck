import Foundation

public protocol GhosttyMaterializing {
    func materializeFramework(from source: URL, to destination: URL) throws
    func cacheFramework(from source: URL, to destination: URL) throws
}

public struct GhosttyMaterializer: GhosttyMaterializing {
    public let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func materializeFramework(from source: URL, to destination: URL) throws {
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try ensureParentExists(for: destination)
        try fileManager.copyItem(at: source, to: destination)
    }

    public func cacheFramework(from source: URL, to destination: URL) throws {
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try ensureParentExists(for: destination)
        try fileManager.copyItem(at: source, to: destination)
    }

    private func ensureParentExists(for path: URL) throws {
        let parent = path.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parent.path) {
            try fileManager.createDirectory(
                at: parent,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }
    }
}
