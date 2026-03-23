import Foundation

public struct ArtifactLayout: Sendable, Equatable {
    public static let logFileName = "log.txt"
    public static let resultBundleFileName = "result.xcresult"
    public static let summaryJSONFileName = "summary.json"
    public static let summaryFileName = "summary.txt"
    public static let indexFileName = "index.json"
    public static let diagnosticsDirectoryName = "diagnostics"
    public static let attachmentsDirectoryName = "attachments"
    public static let appStdoutStderrFileName = "app-stdout-stderr.txt"
    public static let recordingFileName = "recording.mp4"
    public static let screenFileName = "screen.png"
    public static let terminalFileName = "terminal.png"
    public static let uiTreeFileName = "ui-tree.txt"

    public let artifactRoot: URL

    public init(artifactRoot: URL) {
        self.artifactRoot = artifactRoot
    }

    public var log: URL { artifactRoot.appendingPathComponent(Self.logFileName) }
    public var resultBundle: URL { artifactRoot.appendingPathComponent(Self.resultBundleFileName) }
    public var summaryJSON: URL { artifactRoot.appendingPathComponent(Self.summaryJSONFileName) }
    public var summary: URL { artifactRoot.appendingPathComponent(Self.summaryFileName) }
    public var index: URL { artifactRoot.appendingPathComponent(Self.indexFileName) }
    public var diagnosticsDirectory: URL { artifactRoot.appendingPathComponent(Self.diagnosticsDirectoryName) }
    public var attachmentsDirectory: URL { artifactRoot.appendingPathComponent(Self.attachmentsDirectoryName) }
    public var appStdoutStderr: URL { artifactRoot.appendingPathComponent(Self.appStdoutStderrFileName) }
    public var recording: URL { artifactRoot.appendingPathComponent(Self.recordingFileName) }
    public var screen: URL { artifactRoot.appendingPathComponent(Self.screenFileName) }
    public var terminal: URL { artifactRoot.appendingPathComponent(Self.terminalFileName) }
    public var uiTree: URL { artifactRoot.appendingPathComponent(Self.uiTreeFileName) }

    public func relativePath(for url: URL) -> String {
        let rootPath = artifactRoot.standardizedFileURL.path
        let candidatePath = url.standardizedFileURL.path

        if candidatePath == rootPath {
            return "."
        }
        if candidatePath.hasPrefix(rootPath + "/") {
            return String(candidatePath.dropFirst(rootPath.count + 1))
        }
        return url.lastPathComponent
    }

    public var stableInspectionPaths: [URL] {
        [
            log,
            resultBundle,
            summaryJSON,
            summary,
            index,
            diagnosticsDirectory,
            attachmentsDirectory,
            appStdoutStderr,
            recording,
            screen,
            terminal,
            uiTree,
        ]
    }
}
