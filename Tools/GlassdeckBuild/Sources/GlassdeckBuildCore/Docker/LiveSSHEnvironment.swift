import Foundation

public struct LiveSSHEnvironment: Sendable, Equatable {
    public let host: String
    public let port: Int
    public let username: String
    public let password: String
    public let privateKeyPath: String
    public let screenshotCapture: Bool

    public init(
        host: String,
        port: Int,
        username: String,
        password: String,
        privateKeyPath: String,
        screenshotCapture: Bool = false
    ) {
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        self.privateKeyPath = privateKeyPath
        self.screenshotCapture = screenshotCapture
    }

    public var launchctlAssignments: [String: String] {
        var assignments: [String: String] = [
            "GLASSDECK_LIVE_SSH_ENABLED": "1",
            "GLASSDECK_LIVE_SSH_HOST": host,
            "GLASSDECK_LIVE_SSH_PORT": String(port),
            "GLASSDECK_LIVE_SSH_USER": username,
            "GLASSDECK_LIVE_SSH_PASSWORD": password,
            "GLASSDECK_LIVE_SSH_KEY_PATH": privateKeyPath,
        ]
        if screenshotCapture {
            assignments["GLASSDECK_UI_SCREENSHOT_CAPTURE"] = "1"
        }
        return assignments
    }

    public var xcodeBuildAssignments: [String: String] {
        var assignments = launchctlAssignments
        for key in launchctlAssignments.keys {
            assignments["SIMCTL_CHILD_\(key)"] = launchctlAssignments[key]
        }
        return assignments
    }

    public func asLaunchctlCommandPairs() -> [String] {
        launchctlAssignments
            .map { "\( $0.key)=\( $0.value)" }
            .sorted()
    }

    public func asXcodeBuildPairs() -> [String] {
        xcodeBuildAssignments
            .map { "\( $0.key)=\( $0.value)" }
            .sorted()
    }
}
