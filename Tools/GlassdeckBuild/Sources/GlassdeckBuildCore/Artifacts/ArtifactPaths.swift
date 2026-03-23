import Foundation

public struct ArtifactRun: Sendable, Hashable {
    public let command: String
    public let runId: String
    public let timestamp: String

    public init(command: String, runId: String, timestamp: String) {
        self.command = command
        self.runId = runId
        self.timestamp = timestamp
    }

    public var identifier: String {
        "\(timestamp)-\(runId)"
    }
}

public struct CommandArtifactPaths: Sendable {
    public let run: ArtifactRun
    public let command: String
    public let timestamp: String
    public let resultBundle: URL
    public let resultLog: URL
    public let artifactRoot: URL
    public let summary: URL
}

public struct ArtifactPaths {
    public enum Error: Swift.Error, LocalizedError {
        case aliasTargetIsNotDirectory(URL)
        case unableToCreateAlias(URL, String)
    }

    public static let defaultRoot = ".build/glassdeck-build"

    public let repoRoot: URL
    public let worker: String
    public let fileManager: FileManager
    public let nowProvider: () -> Date

    private let runDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()

    public init(
        repoRoot: URL,
        worker: String = "default",
        fileManager: FileManager = .default,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.repoRoot = repoRoot
        self.worker = worker
        self.fileManager = fileManager
        self.nowProvider = nowProvider
    }

    public var buildRoot: URL {
        repoRoot.appendingPathComponent(Self.defaultRoot)
    }

    public var derivedDataRoot: URL {
        buildRoot.appendingPathComponent("derived-data").appendingPathComponent(worker)
    }

    public var resultsRoot: URL {
        buildRoot.appendingPathComponent("results")
    }

    public var logsRoot: URL {
        buildRoot.appendingPathComponent("logs")
    }

    public var artifactsRoot: URL {
        buildRoot.appendingPathComponent("artifacts")
    }

    public var ghosttyCacheRoot: URL {
        buildRoot.appendingPathComponent("ghostty-cache")
    }

    public func formatRunTimestamp(_ date: Date) -> String {
        runDateFormatter.string(from: date)
    }

    public func makeRun(
        command: String,
        runId: String,
        timestamp: String? = nil
    ) -> ArtifactRun {
        let effectiveTimestamp = timestamp ?? formatRunTimestamp(nowProvider())
        return ArtifactRun(command: command, runId: runId, timestamp: effectiveTimestamp)
    }

    public func paths(for run: ArtifactRun) -> CommandArtifactPaths {
        let commandName = sanitizeCommand(run.command)
        let runRoot = artifactsRoot
            .appendingPathComponent(commandName)
            .appendingPathComponent(run.identifier)

        let resultRoot = resultsRoot.appendingPathComponent(commandName)
        let logRoot = logsRoot.appendingPathComponent(commandName)

        return CommandArtifactPaths(
            run: run,
            command: commandName,
            timestamp: run.timestamp,
            resultBundle: resultRoot.appendingPathComponent("\(run.identifier).xcresult"),
            resultLog: logRoot.appendingPathComponent("\(run.identifier).log"),
            artifactRoot: runRoot,
            summary: runRoot.appendingPathComponent("summary.txt")
        )
    }

    public func ensureDirectoryLayout() throws {
        for path in [buildRoot, derivedDataRoot, resultsRoot, logsRoot, artifactsRoot, ghosttyCacheRoot] {
            try ensureDirectoryExists(at: path)
        }
    }

    public func ensureCommandRoots(for command: String) throws {
        let commandName = sanitizeCommand(command)
        try ensureDirectoryExists(at: resultsRoot.appendingPathComponent(commandName))
        try ensureDirectoryExists(at: logsRoot.appendingPathComponent(commandName))
        try ensureDirectoryExists(at: artifactsRoot.appendingPathComponent(commandName))
    }

    public func updateLatestAlias(for run: ArtifactRun) throws {
        let commandName = sanitizeCommand(run.command)
        let commandArtifactsRoot = artifactsRoot.appendingPathComponent(commandName)
        let alias = commandArtifactsRoot.appendingPathComponent("latest")
        let target = commandArtifactsRoot.appendingPathComponent(run.identifier)

        if fileManager.fileExists(atPath: alias.path) {
            try fileManager.removeItem(at: alias)
        }
        try ensureDirectoryExists(at: commandArtifactsRoot)

        do {
            try fileManager.createSymbolicLink(at: alias, withDestinationURL: target)
        } catch {
            throw Error.unableToCreateAlias(alias, "\(error)")
        }
    }

    private func sanitizeCommand(_ command: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let sanitized = command
            .unicodeScalars
            .map { allowed.contains($0) ? Character($0) : "-" }
            .map(String.init)
            .joined()
        return sanitized.isEmpty ? "default" : sanitized
    }

    private func ensureDirectoryExists(at url: URL) throws {
        if !fileManager.fileExists(atPath: url.path) {
            try fileManager.createDirectory(
                at: url,
                withIntermediateDirectories: true,
                attributes: nil
            )
        } else {
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue {
                throw Error.aliasTargetIsNotDirectory(url)
            }
        }
    }
}
