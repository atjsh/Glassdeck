import Foundation

public struct SimulatorEnvironment: Sendable {
    public let host: String
    public let port: Int
    public let username: String
    public let password: String
    public let keyPath: String
    public let screenshotCapture: Bool

    public init(
        host: String,
        port: Int,
        username: String,
        password: String,
        keyPath: String,
        screenshotCapture: Bool = false
    ) {
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        self.keyPath = keyPath
        self.screenshotCapture = screenshotCapture
    }

    private var baseAssignments: [(String, String)] {
        var pairs: [(String, String)] = [
            ("GLASSDECK_LIVE_SSH_ENABLED", "1"),
            ("GLASSDECK_LIVE_SSH_HOST", host),
            ("GLASSDECK_LIVE_SSH_PORT", String(port)),
            ("GLASSDECK_LIVE_SSH_USER", username),
            ("GLASSDECK_LIVE_SSH_PASSWORD", password),
            ("GLASSDECK_LIVE_SSH_KEY_PATH", keyPath),
        ]
        if screenshotCapture {
            pairs.append(("GLASSDECK_UI_SCREENSHOT_CAPTURE", "1"))
        }
        return pairs
    }

    public var launchctlAssignments: [String: String] {
        Dictionary(uniqueKeysWithValues: baseAssignments)
    }

    public var xcodeBuildAssignments: [String: String] {
        var assignments = Dictionary(uniqueKeysWithValues: baseAssignments)
        for (key, value) in baseAssignments where key.hasPrefix("GLASSDECK_") {
            assignments["SIMCTL_CHILD_\(key)"] = value
        }
        return assignments
    }

    public func launchctlSetenvInvocations(simulatorIdentifier: String, simctlExecutable: String = "/usr/bin/env") -> [ProcessInvocation] {
        baseAssignments.map { key, value in
            ProcessInvocation(
                executable: simctlExecutable,
                arguments: ["xcrun", "simctl", "spawn", simulatorIdentifier, "launchctl", "setenv", key, value]
            )
        }
    }

    public func launchctlUnsetenvInvocations(simulatorIdentifier: String, simctlExecutable: String = "/usr/bin/env") -> [ProcessInvocation] {
        baseAssignments.map { key, _ in
            ProcessInvocation(
                executable: simctlExecutable,
                arguments: ["xcrun", "simctl", "spawn", simulatorIdentifier, "launchctl", "unsetenv", key]
            )
        }
    }

    public func xcodeBuildArgumentList() -> [String] {
        xcodeBuildAssignments
            .map { "\( $0.key)=\($0.value)" }
            .sorted()
    }
}
