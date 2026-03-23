import Foundation

public enum SimulatorBootError: Error, LocalizedError {
    case runnerError(Error)

    public var errorDescription: String? {
        switch self {
        case let .runnerError(error):
            "Simulator boot command failed: \(error)"
        }
    }
}

public struct SimulatorBoot {
    public let processRunner: ProcessRunner
    public let simctlExecutable: String
    public let openExecutable: String

    public init(
        processRunner: ProcessRunner = DefaultProcessRunner(),
        simctlExecutable: String = "/usr/bin/env",
        openExecutable: String = "/usr/bin/open"
    ) {
        self.processRunner = processRunner
        self.simctlExecutable = simctlExecutable
        self.openExecutable = openExecutable
    }

    public func boot(simulatorIdentifier: String, openSimulator: Bool = true) async throws {
        let invocations = try bootInvocationChain(simulatorIdentifier: simulatorIdentifier, openSimulator: openSimulator)
        for invocation in invocations {
            do {
                _ = try await processRunner.run(invocation)
            } catch let error as ProcessRunnerError {
                if shouldIgnore(error: error, for: invocation) { continue }
                throw SimulatorBootError.runnerError(error)
            }
        }
    }

    public func bootInvocationChain(
        simulatorIdentifier: String,
        openSimulator: Bool = true
    ) throws -> [ProcessInvocation] {
        guard !simulatorIdentifier.isEmpty else {
            throw SimulatorBootError.runnerError(
                ProcessRunnerError.launchFailed(NSError(domain: "SimulatorBoot", code: 1))
            )
        }

        var invocations: [ProcessInvocation] = []
        if openSimulator {
            invocations.append(ProcessInvocation(executable: openExecutable, arguments: ["-a", "Simulator"]))
        }
        invocations.append(
            ProcessInvocation(
                executable: simctlExecutable,
                arguments: ["xcrun", "simctl", "boot", simulatorIdentifier]
            )
        )
        invocations.append(
            ProcessInvocation(
                executable: simctlExecutable,
                arguments: ["xcrun", "simctl", "bootstatus", simulatorIdentifier, "-b"]
            )
        )
        return invocations
    }

    private func shouldIgnore(error: ProcessRunnerError, for invocation: ProcessInvocation) -> Bool {
        guard invocation.arguments.count >= 4,
              invocation.arguments[0] == "xcrun",
              invocation.arguments[1] == "simctl",
              invocation.arguments[2] == "boot" else {
            return false
        }

        switch error {
        case let .nonzeroExit(result):
            let combined = "\(result.standardOutput)\n\(result.standardError)"
                .lowercased()
            return combined.contains("current state: booted") ||
                combined.contains("unable to boot this device because it is already booted")
        default:
            return false
        }
    }
}
