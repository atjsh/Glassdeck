import Foundation

public enum XcodeAction: String, CaseIterable, Sendable {
    case build = "build"
    case buildForTesting = "build-for-testing"
    case test = "test"
    case testWithoutBuilding = "test-without-building"

    public var xcodebuildArgument: String {
        rawValue
    }

    public var artifactCommand: String {
        switch self {
        case .build, .buildForTesting:
            return "build"
        case .test, .testWithoutBuilding:
            return "test"
        }
    }
}
