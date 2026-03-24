import Foundation

public enum DockerComposeError: Error, LocalizedError {
    case containerNotReady
    case containerStillStarting(attempt: Int, attempts: Int)

    public var errorDescription: String? {
        switch self {
        case .containerNotReady:
            "Docker SSH fixture container could not be resolved."
        case let .containerStillStarting(attempt: attempt, attempts: attempts):
            "Container is not healthy yet (attempt \(attempt)/\(attempts))."
        }
    }
}

public struct DockerComposeConfiguration: Sendable {
    public let projectName: String
    public let composeFile: URL
    public let runtimeDirectory: URL?
    public let dockerExecutable: String
    public let environment: [String: String]

    public init(
        projectName: String,
        composeFile: URL,
        runtimeDirectory: URL? = nil,
        dockerExecutable: String = "/usr/bin/env",
        environment: [String: String] = [:]
    ) {
        self.projectName = projectName
        self.composeFile = composeFile
        self.runtimeDirectory = runtimeDirectory
        self.dockerExecutable = dockerExecutable
        self.environment = environment
    }
}

public final class DockerComposeController {
    public let processRunner: ProcessRunner
    public let configuration: DockerComposeConfiguration

    public init(
        processRunner: ProcessRunner = DefaultProcessRunner(),
        configuration: DockerComposeConfiguration
    ) {
        self.processRunner = processRunner
        self.configuration = configuration
    }

    public func composeInvocation(
        _ action: [String],
        outputMode: ProcessOutputMode = .captureOnly
    ) -> ProcessInvocation {
        let base = ["docker", "compose", "--project-name", configuration.projectName, "-f", configuration.composeFile.path]
        return ProcessInvocation(
            executable: configuration.dockerExecutable,
            arguments: base + action,
            workingDirectory: configuration.runtimeDirectory ?? configuration.composeFile.deletingLastPathComponent(),
            environment: configuration.environment,
            outputMode: outputMode
        )
    }

    public func upInvocation() -> ProcessInvocation {
        composeInvocation(
            ["up", "-d", "--build", "--remove-orphans"],
            outputMode: .captureAndStreamTimestamped
        )
    }

    public func downInvocation() -> ProcessInvocation {
        composeInvocation(
            ["down", "--remove-orphans"],
            outputMode: .captureAndStreamTimestamped
        )
    }

    public func psInvocation() -> ProcessInvocation {
        composeInvocation(["ps", "-q", "ssh"])
    }

    public func inspectHealthStringInvocation(containerID: String) -> ProcessInvocation {
        ProcessInvocation(
            executable: configuration.dockerExecutable,
            arguments: [
                "docker",
                "inspect",
                "--format",
                "{{if .State.Health}}{{.State.Health.Status}}{{else}}unknown{{end}}",
                containerID,
            ],
            workingDirectory: configuration.runtimeDirectory ?? configuration.composeFile.deletingLastPathComponent(),
            environment: configuration.environment
        )
    }

    public func checkVersionInvocation() -> ProcessInvocation {
        ProcessInvocation(
            executable: configuration.dockerExecutable,
            arguments: ["docker", "compose", "version"]
        )
    }

    public func start() async throws {
        _ = try await processRunner.run(upInvocation())
    }

    public func stop() async throws {
        _ = try await processRunner.run(downInvocation())
    }

    public func ensureDockerCompose() async throws {
        _ = try await processRunner.run(checkVersionInvocation())
    }

    public func containerIdentifier() async throws -> String? {
        let result = try await processRunner.run(psInvocation())
        return result.standardOutput
            .components(separatedBy: .newlines)
            .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    }

    public func containerHealth(containerIdentifier: String) async throws -> String {
        let result = try await processRunner.run(inspectHealthStringInvocation(containerID: containerIdentifier))
        let status = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return status
    }

    public func waitForHealthy(
        maxAttempts: Int = 60,
        pollDelayNanos: UInt64 = 1_000_000_000
    ) async throws {
        for attempt in 1 ... maxAttempts {
            guard let container = try await containerIdentifier()?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !container.isEmpty else {
                throw DockerComposeError.containerNotReady
            }
            let status = try await containerHealth(containerIdentifier: container)
            if status == "healthy" {
                return
            }
            if attempt == maxAttempts {
                throw DockerComposeError.containerStillStarting(attempt: attempt, attempts: maxAttempts)
            }
            try await Task.sleep(nanoseconds: pollDelayNanos)
        }
    }
}
