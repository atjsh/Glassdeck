import Foundation

public struct ResultBundleLocator {
    public enum Error: Swift.Error, LocalizedError {
        case missingResultBundle(URL)

        public var errorDescription: String? {
            switch self {
            case let .missingResultBundle(path):
                return "Expected result bundle does not exist: \(path.path)"
            }
        }
    }

    public let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func resolve(preferredPath: URL) throws -> URL {
        guard fileManager.fileExists(atPath: preferredPath.path) else {
            throw Error.missingResultBundle(preferredPath)
        }
        return preferredPath
    }
}
