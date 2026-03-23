import Foundation

public struct XCResultExportResult: Sendable, Equatable {
    public let entries: [ArtifactIndexEntry]
    public let anomalies: [String]

    public init(entries: [ArtifactIndexEntry] = [], anomalies: [String] = []) {
        self.entries = entries
        self.anomalies = anomalies
    }
}

public protocol XCResultExporting {
    func export(resultBundle: URL, outputDirectory: URL) async throws -> XCResultExportResult
}

public struct XCResultExporter: XCResultExporting {
    public enum Error: Swift.Error, LocalizedError {
        case missingResultBundle(URL)
        case writeFailed(URL, String)
    }

    public let processRunner: ProcessRunner
    public let commandPath: String
    public let fileManager: FileManager
    public let nowProvider: @Sendable () -> Date

    public init(
        processRunner: ProcessRunner = DefaultProcessRunner(),
        commandPath: String = "/usr/bin/xcrun",
        fileManager: FileManager = .default,
        nowProvider: @escaping @Sendable () -> Date = Date.init
    ) {
        self.processRunner = processRunner
        self.commandPath = commandPath
        self.fileManager = fileManager
        self.nowProvider = nowProvider
    }

    public func export(resultBundle: URL, outputDirectory: URL) async throws -> XCResultExportResult {
        guard fileManager.fileExists(atPath: resultBundle.path) else {
            throw Error.missingResultBundle(resultBundle)
        }

        if !fileManager.fileExists(atPath: outputDirectory.path) {
            try fileManager.createDirectory(
                at: outputDirectory,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }

        let layout = ArtifactLayout(artifactRoot: outputDirectory)
        var entries: [ArtifactIndexEntry] = []
        var anomalies: [String] = []

        let summaryAnomaly = await exportSummaryJSON(
            resultBundle: resultBundle,
            destination: layout.summaryJSON
        )
        if let summaryAnomaly {
            anomalies.append(summaryAnomaly)
        }
        entries.append(
            makeEntry(
                phase: "03-summary-json",
                kind: "json",
                path: layout.relativePath(for: layout.summaryJSON)
            )
        )

        let diagnosticsAnomaly = await exportOptionalDirectory(
            subcommand: "diagnostics",
            resultBundle: resultBundle,
            destination: layout.diagnosticsDirectory
        )
        if fileManager.fileExists(atPath: layout.diagnosticsDirectory.path) {
            entries.append(
                makeEntry(
                    phase: "04-diagnostics",
                    kind: "directory",
                    path: layout.relativePath(for: layout.diagnosticsDirectory)
                )
            )
        }
        if let diagnosticsAnomaly {
            anomalies.append(diagnosticsAnomaly)
        }

        if let appLog = findAppStdoutAndStderr(in: layout.diagnosticsDirectory) {
            if let aliasAnomaly = createStableAlias(from: appLog, to: layout.appStdoutStderr) {
                anomalies.append(aliasAnomaly)
            } else {
                entries.append(
                    makeEntry(
                        phase: "05-app-stdout-stderr",
                        kind: "text",
                        path: layout.relativePath(for: layout.appStdoutStderr)
                    )
                )
            }
        }

        let attachmentsAnomaly = await exportOptionalDirectory(
            subcommand: "attachments",
            resultBundle: resultBundle,
            destination: layout.attachmentsDirectory
        )
        if fileManager.fileExists(atPath: layout.attachmentsDirectory.path) {
            entries.append(
                makeEntry(
                    phase: "06-attachments",
                    kind: "directory",
                    path: layout.relativePath(for: layout.attachmentsDirectory)
                )
            )
        }
        if let attachmentsAnomaly {
            anomalies.append(attachmentsAnomaly)
        }

        if let recording = findRecording(in: layout.attachmentsDirectory) {
            if let aliasAnomaly = createStableAlias(from: recording, to: layout.recording) {
                anomalies.append(aliasAnomaly)
            } else {
                entries.append(
                    makeEntry(
                        phase: "07-recording",
                        kind: "video",
                        path: layout.relativePath(for: layout.recording)
                    )
                )
            }
        }

        if let screen = findScreen(in: layout.attachmentsDirectory) {
            if let aliasAnomaly = createStableAlias(from: screen, to: layout.screen) {
                anomalies.append(aliasAnomaly)
            } else {
                entries.append(
                    makeEntry(
                        phase: "08-screen",
                        kind: "image",
                        path: layout.relativePath(for: layout.screen)
                    )
                )
            }
        }

        if let terminal = findTerminal(in: layout.attachmentsDirectory) {
            if let aliasAnomaly = createStableAlias(from: terminal, to: layout.terminal) {
                anomalies.append(aliasAnomaly)
            } else {
                entries.append(
                    makeEntry(
                        phase: "09-terminal",
                        kind: "image",
                        path: layout.relativePath(for: layout.terminal)
                    )
                )
            }
        }

        if let uiTree = findUiTree(in: layout.diagnosticsDirectory) {
            if let aliasAnomaly = createStableAlias(from: uiTree, to: layout.uiTree) {
                anomalies.append(aliasAnomaly)
            } else {
                entries.append(
                    makeEntry(
                        phase: "10-ui-tree",
                        kind: "text",
                        path: layout.relativePath(for: layout.uiTree)
                    )
                )
            }
        }

        return XCResultExportResult(entries: entries, anomalies: anomalies)
    }

    private func exportSummaryJSON(
        resultBundle: URL,
        destination: URL
    ) async -> String? {
        let invocation = ProcessInvocation(
            executable: commandPath,
            arguments: [
                "xcresulttool",
                "get",
                "--legacy",
                "--format",
                "json",
                "--path",
                resultBundle.path,
            ]
        )

        var content = ""
        var anomaly: String?

        do {
            let result = try await processRunner.run(invocation)
            content = result.standardOutput
            if content.isEmpty {
                anomaly = "xcresult-summary-empty"
            }
        } catch let error as ProcessRunnerError {
            switch error {
            case let .nonzeroExit(result):
                content = result.standardOutput.isEmpty ? result.standardError : result.standardOutput
                anomaly = "xcresult-summary-export-failed: exit-code=\(result.exitCode)"
            default:
                anomaly = "xcresult-summary-export-failed: \(error)"
            }
        } catch {
            anomaly = "xcresult-summary-export-failed: \(error)"
        }

        do {
            try content.write(to: destination, atomically: true, encoding: .utf8)
        } catch {
            return "xcresult-summary-write-failed: \(error)"
        }

        return anomaly
    }

    private func exportOptionalDirectory(
        subcommand: String,
        resultBundle: URL,
        destination: URL
    ) async -> String? {
        let invocation = ProcessInvocation(
            executable: commandPath,
            arguments: [
                "xcresulttool",
                "export",
                subcommand,
                "--path",
                resultBundle.path,
                "--output-path",
                destination.path,
            ]
        )

        do {
            _ = try await processRunner.run(invocation)
            return nil
        } catch let error as ProcessRunnerError {
            switch error {
            case let .nonzeroExit(result):
                return "xcresult-\(subcommand)-export-failed: exit-code=\(result.exitCode)"
            default:
                return "xcresult-\(subcommand)-export-failed: \(error)"
            }
        } catch {
            return "xcresult-\(subcommand)-export-failed: \(error)"
        }
    }

    private func createStableAlias(from source: URL, to destination: URL) -> String? {
        guard fileManager.fileExists(atPath: source.path) else {
            return nil
        }
        do {
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.createSymbolicLink(at: destination, withDestinationURL: source)
            return nil
        } catch {
            return "xcresult-alias-failed: \(destination.lastPathComponent): \(error)"
        }
    }

    private func findAppStdoutAndStderr(in diagnosticsDirectory: URL) -> URL? {
        guard fileManager.fileExists(atPath: diagnosticsDirectory.path),
              let enumerator = fileManager.enumerator(
                at: diagnosticsDirectory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
              )
        else {
            return nil
        }

        var matches: [URL] = []
        for case let fileURL as URL in enumerator {
            let name = fileURL.lastPathComponent
            if name.hasPrefix("StandardOutputAndStandardError"),
               fileManager.fileExists(atPath: fileURL.path) {
                matches.append(fileURL)
            }
        }

        return matches.sorted { lhs, rhs in
            let lhsSpecific = lhs.lastPathComponent.contains("-")
            let rhsSpecific = rhs.lastPathComponent.contains("-")
            if lhsSpecific != rhsSpecific {
                return lhsSpecific && !rhsSpecific
            }
            return lhs.lastPathComponent < rhs.lastPathComponent
        }.first
    }

    private func findRecording(in attachmentsDirectory: URL) -> URL? {
        if let matchingFromManifest = findAttachment(
            in: attachmentsDirectory,
            manifestMatch: { item in
                let suggestion = item.suggestedHumanReadableName?.lowercased() ?? ""
                return suggestion.contains("screen recording")
                    || item.exportedFileName.lowercased().hasSuffix(".mp4")
            },
            fallbackMatch: { fileURL in
                fileURL.pathExtension.lowercased() == "mp4"
            }
        ) {
            return matchingFromManifest
        }

        return nil
    }

    private func findScreen(in attachmentsDirectory: URL) -> URL? {
        return findAttachment(
            in: attachmentsDirectory,
            manifestMatch: { item in
                let suggestion = item.suggestedHumanReadableName?.lowercased() ?? ""
                let fileName = item.exportedFileName.lowercased()
                return fileName.hasSuffix(".png")
                    && (fileName.contains("screen") || suggestion.contains("screen"))
            },
            fallbackMatch: { fileURL in
                fileURL.pathExtension.lowercased() == "png"
                    && fileURL.lastPathComponent.lowercased().contains("screen")
            }
        )
    }

    private func findTerminal(in attachmentsDirectory: URL) -> URL? {
        return findAttachment(
            in: attachmentsDirectory,
            manifestMatch: { item in
                let suggestion = item.suggestedHumanReadableName?.lowercased() ?? ""
                let fileName = item.exportedFileName.lowercased()
                return fileName.hasSuffix(".png")
                    && (fileName.contains("terminal") || suggestion.contains("terminal"))
            },
            fallbackMatch: { fileURL in
                fileURL.pathExtension.lowercased() == "png"
                    && fileURL.lastPathComponent.lowercased().contains("terminal")
            }
        )
    }

    private func findUiTree(in diagnosticsDirectory: URL) -> URL? {
        if !fileManager.fileExists(atPath: diagnosticsDirectory.path) {
            return nil
        }

        let explicit = diagnosticsDirectory.appendingPathComponent(ArtifactLayout.uiTreeFileName)
        if fileManager.fileExists(atPath: explicit.path) {
            return explicit
        }

        guard let enumerator = fileManager.enumerator(
            at: diagnosticsDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        let matches: [URL] = enumerator.compactMap { element in
            guard let fileURL = element as? URL else { return nil }
            let name = fileURL.lastPathComponent.lowercased()
            guard name.hasSuffix(".txt") else { return nil }
            if name.contains("ui-tree") {
                return fileURL
            }
            return nil
        }

        return matches.sorted { lhs, rhs in
            lhs.path < rhs.path
        }.first
    }

    private func findAttachment(
        in attachmentsDirectory: URL,
        manifestMatch: (AttachmentManifestItem) -> Bool,
        fallbackMatch: ((URL) -> Bool)? = nil
    ) -> URL? {
        if let matchingFromManifest = findMatchingManifestItem(
            in: attachmentsDirectory,
            match: manifestMatch
        ) {
            return matchingFromManifest
        }

        guard let fallbackMatch else {
            return nil
        }

        guard let enumerator = fileManager.enumerator(
            at: attachmentsDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        var matches: [URL] = []
        for case let fileURL as URL in enumerator {
            if fallbackMatch(fileURL) {
                matches.append(fileURL)
            }
        }

        return matches.sorted { lhs, rhs in
            lhs.path < rhs.path
        }.first
    }

    private func findMatchingManifestItem(
        in attachmentsDirectory: URL,
        match: (AttachmentManifestItem) -> Bool
    ) -> URL? {
        let manifestPath = attachmentsDirectory.appendingPathComponent("manifest.json")
        guard let manifestData = try? Data(contentsOf: manifestPath),
              let manifest = try? JSONDecoder().decode([AttachmentManifestRecord].self, from: manifestData) else {
            return nil
        }

        let matches = manifest.flatMap(\.attachments).filter(match)
        for match in matches {
            let candidate = attachmentsDirectory.appendingPathComponent(match.exportedFileName)
            if fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    private func makeEntry(
        phase: String,
        kind: String,
        path: String
    ) -> ArtifactIndexEntry {
        ArtifactIndexEntry(
            phase: phase,
            kind: kind,
            path: path,
            timestamp: nowProvider()
        )
    }
}

private struct AttachmentManifestRecord: Decodable {
    let attachments: [AttachmentManifestItem]
}

private struct AttachmentManifestItem: Decodable {
    let exportedFileName: String
    let suggestedHumanReadableName: String?
}
