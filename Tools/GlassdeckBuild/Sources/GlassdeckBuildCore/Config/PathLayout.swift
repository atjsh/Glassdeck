import Foundation

public struct PathLayout: Sendable {
    public enum OutputKind: String {
        case command = "commands"
        case result = "results"
        case log = "logs"
        case artifact = "artifacts"
        case derivedData = "derived-data"
        case ghosttyCache = "ghostty-cache"
    }

    public let workspace: WorkspaceContext
    public let worker: WorkerScope
    public let baseRelativeRoot: String

    public init(workspace: WorkspaceContext = .current(), worker: WorkerScope = .default) {
        self.workspace = workspace
        self.worker = worker
        self.baseRelativeRoot = ".build/glassdeck-build"
    }

    public var root: URL {
        workspace.workspaceRoot.appendingPathComponent(baseRelativeRoot)
    }

    public var workerRoot: URL {
        derivedDataRoot.appendingPathComponent(worker.slug)
    }

    public var derivedDataRoot: URL {
        root.appendingPathComponent(OutputKind.derivedData.rawValue)
    }

    public func commandRoot(_ commandName: String) -> URL {
        root.appendingPathComponent(commandName)
    }

    public func resultBundlePath(for commandName: String, timestamp: String) -> URL {
        commandRoot(commandName)
            .appendingPathComponent(OutputKind.result.rawValue)
            .appendingPathComponent(timestamp)
            .appendingPathExtension("xcresult")
    }

    public func logFilePath(for commandName: String, timestamp: String) -> URL {
        commandRoot(commandName)
            .appendingPathComponent(OutputKind.log.rawValue)
            .appendingPathComponent(timestamp)
            .appendingPathExtension("log")
    }

    public func artifactRoot(for commandName: String, timestamp: String) -> URL {
        commandRoot(commandName)
            .appendingPathComponent(OutputKind.artifact.rawValue)
            .appendingPathComponent(timestamp)
    }

    public func artifactLatestLink(for commandName: String) -> URL {
        commandRoot(commandName)
            .appendingPathComponent(OutputKind.artifact.rawValue)
            .appendingPathComponent("latest")
    }

    public func ghosttyCacheRoot() -> URL {
        root.appendingPathComponent(OutputKind.ghosttyCache.rawValue)
    }
}
