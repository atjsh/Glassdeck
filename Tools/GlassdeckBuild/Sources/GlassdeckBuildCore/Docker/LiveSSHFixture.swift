import Foundation

public struct LiveSSHFixtureConfiguration: Sendable {
    public let dockerHostPort: Int
    public let username: String
    public let password: String
    public let privateKeyPath: String
    public let screenshotCapture: Bool

    public init(
        dockerHostPort: Int,
        username: String,
        password: String,
        privateKeyPath: String,
        screenshotCapture: Bool = false
    ) {
        self.dockerHostPort = dockerHostPort
        self.username = username
        self.password = password
        self.privateKeyPath = privateKeyPath
        self.screenshotCapture = screenshotCapture
    }
}

public final class LiveSSHFixture {
    public let docker: DockerComposeController
    public let hostResolver: HostIPResolver
    public let configuration: LiveSSHFixtureConfiguration

    public init(
        docker: DockerComposeController,
        hostResolver: HostIPResolver,
        configuration: LiveSSHFixtureConfiguration
    ) {
        self.docker = docker
        self.hostResolver = hostResolver
        self.configuration = configuration
    }

    public func start() async throws -> LiveSSHEnvironment {
        try await docker.start()
        try await docker.waitForHealthy()
        let host = try await hostResolver.resolveLANIP()
        return makeEnvironment(host: host)
    }

    public func stop() async throws {
        try await docker.stop()
    }

    public func makeEnvironment(host: String) -> LiveSSHEnvironment {
        LiveSSHEnvironment(
            host: host,
            port: configuration.dockerHostPort,
            username: configuration.username,
            password: configuration.password,
            privateKeyPath: configuration.privateKeyPath,
            screenshotCapture: configuration.screenshotCapture
        )
    }
}
