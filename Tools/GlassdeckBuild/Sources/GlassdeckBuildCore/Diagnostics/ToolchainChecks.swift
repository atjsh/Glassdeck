import Foundation

public struct ToolchainChecks: Sendable {
    public typealias ExecutableResolver = @Sendable (String) -> URL?
    public let resolveExecutable: ExecutableResolver

    public init(resolveExecutable: @escaping ExecutableResolver = ToolchainChecks.defaultExecutableResolver) {
        self.resolveExecutable = resolveExecutable
    }

    public func run() -> [DiagnosticIssue] {
        var issues: [DiagnosticIssue] = []

        issues.append(
            contentsOf: validate(tool: "xcodebuild", for: "Toolchain")
        )
        issues.append(
            contentsOf: validate(tool: "swift", for: "Toolchain")
        )
        issues.append(
            contentsOf: validate(tool: "xcrun", for: "Toolchain")
        )

        return issues
    }

    private func validate(tool: String, for area: String) -> [DiagnosticIssue] {
        guard let path = resolveExecutable(tool) else {
            return [
                DiagnosticIssue(
                    area: area,
                    check: "\(tool)-exists",
                    severity: .error,
                    message: "Required executable '\(tool)' was not found.",
                    details: "Ensure Xcode command-line tools are installed and PATH includes \(tool)."
                )
            ]
        }
        return [
            DiagnosticIssue(
                area: area,
                check: "\(tool)-exists",
                severity: .info,
                message: "Found \(tool) at \(path.path)."
            )
        ]
    }

    public static func defaultExecutableResolver(_ command: String) -> URL? {
        let env = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let paths = env.split(separator: ":").map(String.init)
        let candidates = paths + ["/usr/bin", "/usr/local/bin", "/opt/homebrew/bin"]

        for base in candidates {
            let url = URL(fileURLWithPath: base).appendingPathComponent(command)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }
}
