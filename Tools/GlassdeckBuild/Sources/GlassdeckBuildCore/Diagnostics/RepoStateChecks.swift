import Foundation

public struct RepoStateChecks {
    public typealias DirectoryCheck = @Sendable (URL) -> Bool

    public let fileManager: FileManager
    public let existsDirectory: DirectoryCheck

    public init(
        fileManager: FileManager = .default,
        existsDirectory: @escaping DirectoryCheck = RepoStateChecks.defaultDirectoryCheck
    ) {
        self.fileManager = fileManager
        self.existsDirectory = existsDirectory
    }

    public func run(at repoRoot: URL) -> [DiagnosticIssue] {
        var issues: [DiagnosticIssue] = []
        let xcodeProject = repoRoot.appendingPathComponent("GlassdeckApp.xcodeproj")
        let frameworkRoot = repoRoot.appendingPathComponent("Frameworks")
        let ghosttyKit = frameworkRoot.appendingPathComponent("GhosttyKit.xcframework")
        let legacyGhostty = frameworkRoot.appendingPathComponent("CGhosttyVT.xcframework")
        let staleGhosttyArtifacts = [
            frameworkRoot.appendingPathComponent("GhosttyKit.xcframework.debug"),
            frameworkRoot.appendingPathComponent("GhosttyKit.xcframework.old-backup"),
        ]
        let vendorRoot = repoRoot.appendingPathComponent("Vendor")
        let ghosttyFork = vendorRoot.appendingPathComponent("ghostty-fork")
        let sshClient = vendorRoot.appendingPathComponent("swift-ssh-client")

        if let issue = ensureFileExists(xcodeProject, area: "Repository", check: "xcode-project") {
            issues.append(issue)
        }
        if let issue = ensureDirectoryExists(ghosttyFork, area: "Repository", check: "ghostty-submodule") {
            issues.append(issue)
        }
        if let issue = ensureDirectoryExists(sshClient, area: "Repository", check: "ssh-client-submodule") {
            issues.append(issue)
        }
        if let issue = validateLegacyBuildDefinitions(repoRoot: repoRoot) {
            issues.append(issue)
        }
        if let issue = validateLegacyArtifact(legacyGhostty) {
            issues.append(issue)
        }
        issues.append(contentsOf: validateStaleGhosttyArtifacts(staleGhosttyArtifacts))
        if let issue = validateStandaloneCheckout(sshClient, dependencyName: "swift-ssh-client") {
            issues.append(issue)
        }
        if let issue = ensureDirectoryExists(frameworkRoot, area: "Repository", check: "framework-root") {
            issues.append(issue)
        }
        if let issue = validateGhosttyFrameworkReadiness(ghosttyKit) {
            issues.append(issue)
        }

        return issues
    }

    private func ensureFileExists(
        _ url: URL,
        area: String,
        check: String
    ) -> DiagnosticIssue? {
        if fileManager.fileExists(atPath: url.path) {
            return nil
        }
        return DiagnosticIssue(
            area: area,
            check: check,
            severity: .warning,
            message: "Expected path does not exist: \(url.path)",
            details: "Some checks may be affected if this path is missing."
        )
    }

    private func ensureDirectoryExists(
        _ url: URL,
        area: String,
        check: String
    ) -> DiagnosticIssue? {
        guard existsDirectory(url) else {
            return DiagnosticIssue(
                area: area,
                check: check,
                severity: .warning,
                message: "Expected directory does not exist: \(url.path)",
                details: "Create this directory or update tooling inputs."
            )
        }
        return nil
    }

    private func validateLegacyArtifact(_ url: URL) -> DiagnosticIssue? {
        if !fileManager.fileExists(atPath: url.path) {
            return nil
        }
        return DiagnosticIssue(
            area: "Repository",
            check: "legacy-ghostty-framework",
            severity: .warning,
            message: "Legacy framework still present: \(url.lastPathComponent)",
            details: "Delete this legacy artifact to enforce submodule-based dependency flow."
        )
    }

    private func validateStaleGhosttyArtifacts(_ urls: [URL]) -> [DiagnosticIssue] {
        urls.compactMap { url in
            guard fileManager.fileExists(atPath: url.path) else {
                return nil
            }
            let checkName = url.lastPathComponent
                .replacingOccurrences(of: ".", with: "-")
            return DiagnosticIssue(
                area: "Repository",
                check: "stale-\(checkName)",
                severity: .warning,
                message: "Stale Ghostty framework artifact present: \(url.lastPathComponent)",
                details: "Delete stale local framework copies so builds and manual inspections use Frameworks/GhosttyKit.xcframework only."
            )
        }
    }

    private func validateLegacyBuildDefinitions(repoRoot: URL) -> DiagnosticIssue? {
        let legacyPaths = [
            repoRoot.appendingPathComponent("project.yml"),
            repoRoot.appendingPathComponent("Package.swift"),
            repoRoot.appendingPathComponent("Package.resolved"),
            repoRoot.appendingPathComponent("Scripts/generate-xcodeproj.sh"),
            repoRoot.appendingPathComponent("Scripts/patch-local-package-product.py"),
            repoRoot.appendingPathComponent("Scripts/build-cghosttyvt.sh"),
        ]
        let present = legacyPaths.filter { fileManager.fileExists(atPath: $0.path) }
        guard !present.isEmpty else {
            return nil
        }

        let details = present
            .map { $0.path.replacingOccurrences(of: repoRoot.path + "/", with: "") }
            .joined(separator: ", ")
        return DiagnosticIssue(
            area: "Repository",
            check: "legacy-build-definitions",
            severity: .warning,
            message: "Legacy XcodeGen-era build files are still present.",
            details: "Remove these retired paths: \(details)"
        )
    }

    private func validateStandaloneCheckout(_ dependencyRoot: URL, dependencyName: String) -> DiagnosticIssue? {
        let gitMarker = dependencyRoot.appendingPathComponent(".git")
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: gitMarker.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }
        return DiagnosticIssue(
            area: "Repository",
            check: "standalone-\(dependencyName)-checkout",
            severity: .warning,
            message: "\(dependencyName) is still a standalone nested git checkout.",
            details: "Convert this dependency to a pinned submodule or remove its embedded .git directory."
        )
    }

    private func validateGhosttyFrameworkReadiness(_ url: URL) -> DiagnosticIssue? {
        guard !existsDirectory(url) else {
            return nil
        }
        return DiagnosticIssue(
            area: "Repository",
            check: "ghostty-framework",
            severity: .warning,
            message: "Local GhosttyKit.xcframework is not materialized yet: \(url.path)",
            details: "Run `swift run --package-path Tools/GlassdeckBuild glassdeck-build deps ghostty` to prepare the local framework before build/test commands that need it."
        )
    }

    public static func defaultDirectoryCheck(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
