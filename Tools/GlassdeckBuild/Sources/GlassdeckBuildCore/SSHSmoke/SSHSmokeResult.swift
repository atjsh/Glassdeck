import Foundation

public struct SSHSmokeResult: Equatable, Sendable {
    public let authentication: String
    public let exitStatus: Int
    public let standardOutput: String
    public let standardError: String

    public init(
        authentication: String,
        exitStatus: Int,
        standardOutput: String,
        standardError: String
    ) {
        self.authentication = authentication
        self.exitStatus = exitStatus
        self.standardOutput = standardOutput
        self.standardError = standardError
    }

    public var isSuccess: Bool {
        exitStatus == 0
    }
}
