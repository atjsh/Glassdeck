import Foundation

public struct SimulatorClipboard: Sendable {
    public let simctlExecutable: String
    public let shellExecutable: String

    public init(
        simctlExecutable: String = "/usr/bin/xcrun",
        shellExecutable: String = "/bin/zsh"
    ) {
        self.simctlExecutable = simctlExecutable
        self.shellExecutable = shellExecutable
    }

    public func copyFileInvocation(
        simulatorIdentifier: String,
        fileURL: URL
    ) -> ProcessInvocation {
        let quotedFilePath = CommandLineRendering.quote(fileURL.path)
        let command = "cat \(quotedFilePath) | \(simctlExecutable) simctl pbcopy \(simulatorIdentifier)"
        return ProcessInvocation(
            executable: shellExecutable,
            arguments: ["-lc", command]
        )
    }

    public func copyTextInvocation(
        simulatorIdentifier: String,
        text: String
    ) -> ProcessInvocation {
        let quotedText = CommandLineRendering.quote(text)
        let command = "printf %s \(quotedText) | \(simctlExecutable) simctl pbcopy \(simulatorIdentifier)"
        return ProcessInvocation(
            executable: shellExecutable,
            arguments: ["-lc", command]
        )
    }
}
