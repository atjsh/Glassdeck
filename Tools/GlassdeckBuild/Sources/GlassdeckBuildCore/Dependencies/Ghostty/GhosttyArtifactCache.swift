import Foundation

public enum GhosttyBuildProfile: String, Sendable {
    case debug
    case releaseFast = "release-fast"

    public var zigOptimize: String {
        switch self {
        case .debug:
            return "Debug"
        case .releaseFast:
            return "ReleaseFast"
        }
    }
}

public struct GhosttyArtifactCache: Sendable {
    public let cacheRoot: URL

    public init(cacheRoot: URL) {
        self.cacheRoot = cacheRoot
    }

    public func profileRoot(commit: String, profile: GhosttyBuildProfile) -> URL {
        cacheRoot
            .appendingPathComponent(commit)
            .appendingPathComponent(profile.rawValue)
    }

    public func xcframeworkPath(commit: String, profile: GhosttyBuildProfile) -> URL {
        profileRoot(commit: commit, profile: profile)
            .appendingPathComponent("GhosttyKit.xcframework")
    }
}
