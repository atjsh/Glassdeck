import Foundation

public struct WorkspaceContext: Equatable, Sendable {
    public let workspaceRoot: URL
    public let projectRootName: String

    public init(workspaceRoot: URL, projectRootName: String = "Glassdeck") {
        self.workspaceRoot = workspaceRoot
        self.projectRootName = projectRootName
    }

    public static func current(
        at path: String = FileManager.default.currentDirectoryPath,
        projectRootName: String = "Glassdeck"
    ) -> WorkspaceContext {
        let fileManager = FileManager.default
        var candidate = URL(fileURLWithPath: path).standardizedFileURL

        while true {
            let nestedProjectRoot = candidate.appendingPathComponent(projectRootName)
            if fileManager.fileExists(
                atPath: nestedProjectRoot
                    .appendingPathComponent("GlassdeckApp.xcodeproj")
                    .path
            ) {
                return WorkspaceContext(
                    workspaceRoot: candidate,
                    projectRootName: projectRootName
                )
            }

            if candidate.lastPathComponent == projectRootName,
               fileManager.fileExists(
                   atPath: candidate
                       .appendingPathComponent("GlassdeckApp.xcodeproj")
                       .path
               ) {
                return WorkspaceContext(
                    workspaceRoot: candidate.deletingLastPathComponent(),
                    projectRootName: projectRootName
                )
            }

            let parent = candidate.deletingLastPathComponent()
            if parent == candidate {
                break
            }
            candidate = parent
        }

        let fallbackRoot = URL(fileURLWithPath: path).lastPathComponent == projectRootName
            ? URL(fileURLWithPath: path).deletingLastPathComponent()
            : URL(fileURLWithPath: path)
        return WorkspaceContext(
            workspaceRoot: fallbackRoot,
            projectRootName: projectRootName
        )
    }

    public var projectRoot: URL {
        workspaceRoot.appendingPathComponent(projectRootName)
    }
}
