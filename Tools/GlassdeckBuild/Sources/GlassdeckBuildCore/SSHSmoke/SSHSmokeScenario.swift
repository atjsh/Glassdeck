import Foundation

public enum SSHSmokeAuthentication: Equatable, Sendable {
    case password(String)
    case privateKey(path: String)

    public var label: String {
        switch self {
        case .password:
            return "password"
        case .privateKey:
            return "private-key"
        }
    }
}

public struct SSHSmokeScenario: Equatable, Sendable {
    public let host: String
    public let port: Int
    public let username: String
    public let command: String
    public let expectedSubstring: String
    public let authentication: SSHSmokeAuthentication

    public init(
        host: String,
        port: Int,
        username: String,
        command: String = "printf GLASSDECK_SSH_SMOKE_OK",
        expectedSubstring: String = "GLASSDECK_SSH_SMOKE_OK",
        authentication: SSHSmokeAuthentication
    ) {
        self.host = host
        self.port = port
        self.username = username
        self.command = command
        self.expectedSubstring = expectedSubstring
        self.authentication = authentication
    }

    public static func password(
        host: String,
        port: Int,
        username: String,
        password: String,
        command: String = "printf GLASSDECK_SSH_SMOKE_OK"
    ) -> SSHSmokeScenario {
        SSHSmokeScenario(
            host: host,
            port: port,
            username: username,
            command: command,
            authentication: .password(password)
        )
    }

    public static func privateKey(
        host: String,
        port: Int,
        username: String,
        privateKeyPath: String,
        command: String = "printf GLASSDECK_SSH_SMOKE_OK"
    ) -> SSHSmokeScenario {
        SSHSmokeScenario(
            host: host,
            port: port,
            username: username,
            command: command,
            authentication: .privateKey(path: privateKeyPath)
        )
    }
}
