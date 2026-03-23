import XCTest
@testable import GlassdeckBuildCore

final class DiagnosticsTests: XCTestCase {
    func testToolchainChecksReportMissingExecutable() {
        let checks = ToolchainChecks(resolveExecutable: { _ in nil })
        let issues = checks.run()

        XCTAssertGreaterThanOrEqual(issues.count, 3)
        XCTAssertTrue(issues.allSatisfy { $0.severity == .error })
        XCTAssertTrue(issues.allSatisfy { $0.message.contains("was not found") })
        XCTAssertFalse(issues.isEmpty)
    }

    func testRepoStateChecksWarnsOnLegacyGhosttyFramework() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("gb-diagnostics-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        try FileManager.default.createDirectory(at: tempRoot.appendingPathComponent("Frameworks"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: tempRoot.appendingPathComponent("Frameworks/CGhosttyVT.xcframework"),
            withIntermediateDirectories: true
        )

        let checks = RepoStateChecks(fileManager: FileManager.default)
        let issues = checks.run(at: tempRoot)

        XCTAssertTrue(issues.contains(where: { $0.check == "legacy-ghostty-framework" }))
        XCTAssertTrue(issues.allSatisfy { $0.severity == .warning || $0.severity == .info })
    }

    func testRepoStateChecksWarnsOnStaleGhosttyArtifacts() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("gb-diagnostics-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        try FileManager.default.createDirectory(
            at: tempRoot.appendingPathComponent("Frameworks/GhosttyKit.xcframework.debug"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: tempRoot.appendingPathComponent("Frameworks/GhosttyKit.xcframework.old-backup"),
            withIntermediateDirectories: true
        )

        let checks = RepoStateChecks(fileManager: FileManager.default)
        let issues = checks.run(at: tempRoot)

        XCTAssertTrue(issues.contains(where: { $0.check == "stale-GhosttyKit-xcframework-debug" }))
        XCTAssertTrue(issues.contains(where: { $0.check == "stale-GhosttyKit-xcframework-old-backup" }))
    }

    func testRepoStateChecksWarnOnLegacyBuildFilesAndStandaloneVendorRepo() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("gb-diagnostics-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        try FileManager.default.createDirectory(at: tempRoot.appendingPathComponent("Frameworks"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tempRoot.appendingPathComponent("Vendor/swift-ssh-client/.git"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tempRoot.appendingPathComponent("Scripts"), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: tempRoot.appendingPathComponent("project.yml").path, contents: Data())
        FileManager.default.createFile(atPath: tempRoot.appendingPathComponent("Package.swift").path, contents: Data())
        FileManager.default.createFile(atPath: tempRoot.appendingPathComponent("Scripts/generate-xcodeproj.sh").path, contents: Data())

        let checks = RepoStateChecks(fileManager: FileManager.default)
        let issues = checks.run(at: tempRoot)

        XCTAssertTrue(issues.contains(where: { $0.check == "legacy-build-definitions" }))
        XCTAssertTrue(issues.contains(where: { $0.check == "standalone-swift-ssh-client-checkout" }))
    }

    func testRepoStateChecksTreatMissingGhosttyFrameworkAsLocalReadinessGuidance() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("gb-diagnostics-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        try FileManager.default.createDirectory(
            at: tempRoot.appendingPathComponent("Frameworks"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: tempRoot.appendingPathComponent("GlassdeckApp.xcodeproj"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: tempRoot.appendingPathComponent("Vendor/ghostty-fork"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: tempRoot.appendingPathComponent("Vendor/swift-ssh-client"),
            withIntermediateDirectories: true
        )

        let checks = RepoStateChecks(fileManager: FileManager.default)
        let issues = checks.run(at: tempRoot)
        let issue = try XCTUnwrap(issues.first(where: { $0.check == "ghostty-framework" }))
        let details = try XCTUnwrap(issue.details)

        XCTAssertTrue(issue.message.contains("GhosttyKit.xcframework"))
        XCTAssertTrue(details.contains("glassdeck-build deps ghostty"))
    }

    func testRepoStateChecksDoesNotWarnForGitfileSubmoduleLayout() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("gb-diagnostics-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        try FileManager.default.createDirectory(
            at: tempRoot.appendingPathComponent("Frameworks"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: tempRoot.appendingPathComponent("GlassdeckApp.xcodeproj"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: tempRoot.appendingPathComponent("Vendor/ghostty-fork"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: tempRoot.appendingPathComponent("Vendor/swift-ssh-client"),
            withIntermediateDirectories: true
        )
        try "gitdir: ../../.git/modules/Vendor/swift-ssh-client\n".write(
            to: tempRoot.appendingPathComponent("Vendor/swift-ssh-client/.git"),
            atomically: true,
            encoding: .utf8
        )

        let checks = RepoStateChecks(fileManager: FileManager.default)
        let issues = checks.run(at: tempRoot)

        XCTAssertFalse(issues.contains(where: { $0.check == "standalone-swift-ssh-client-checkout" }))
    }

    func testDoctorReportRendersInPriorityOrder() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("gb-diagnostics-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tempRoot.appendingPathComponent("Frameworks"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tempRoot.appendingPathComponent("Vendor"), withIntermediateDirectories: true)

        let report = DoctorChecks(
            toolchainChecks: ToolchainChecks(resolveExecutable: { _ in nil }),
            repoStateChecks: RepoStateChecks(fileManager: FileManager.default)
        ).run(repoRoot: tempRoot)

        let rendered = report.renderText()
        XCTAssertTrue(rendered.contains("[error]"))
        XCTAssertTrue(rendered.contains("[warning]"))
        XCTAssertTrue(rendered.contains("No issues.") == false)
    }
}
