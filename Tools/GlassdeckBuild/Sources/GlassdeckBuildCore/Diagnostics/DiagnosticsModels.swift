import Foundation

public enum DiagnosticSeverity: String, Codable, Sendable {
    case info
    case warning
    case error
}

public struct DiagnosticIssue: Codable, Equatable, Sendable {
    public let area: String
    public let check: String
    public let severity: DiagnosticSeverity
    public let message: String
    public let details: String?

    public init(
        area: String,
        check: String,
        severity: DiagnosticSeverity,
        message: String,
        details: String? = nil
    ) {
        self.area = area
        self.check = check
        self.severity = severity
        self.message = message
        self.details = details
    }
}

public struct DiagnosticsReport: Codable, Equatable, Sendable {
    public let issues: [DiagnosticIssue]

    public init(issues: [DiagnosticIssue]) {
        self.issues = issues
    }

    public var hasErrors: Bool {
        issues.contains { $0.severity == .error }
    }

    public func renderText() -> String {
        if issues.isEmpty {
            return "No issues."
        }

        return issues
            .sorted(by: { left, right in
                guard left.severity != right.severity else {
                    return left.check < right.check
                }
                return Self.severityRank(left.severity) > Self.severityRank(right.severity)
            })
            .map {
                let issue = $0
                return "[\(issue.severity.rawValue)] \(issue.area).\(issue.check): \(issue.message)" +
                (issue.details.map { "\n  - \($0)" } ?? "")
            }
            .joined(separator: "\n")
    }

    private static func severityRank(_ severity: DiagnosticSeverity) -> Int {
        switch severity {
        case .error:
            3
        case .warning:
            2
        case .info:
            1
        }
    }
}
