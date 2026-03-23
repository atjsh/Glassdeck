import ArgumentParser

public enum XcodeOutputMode: String, Codable, ExpressibleByArgument {
    case filtered
    case full
    case quiet

    var processOutputMode: ProcessOutputMode {
        switch self {
        case .filtered:
            .captureAndStreamTimestampedFiltered(.xcodebuild)
        case .full:
            .captureAndStreamTimestamped
        case .quiet:
            .captureOnly
        }
    }
}
