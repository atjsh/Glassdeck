import XCTest
@testable import GlassdeckBuildCore

final class HostIPResolverTests: XCTestCase {
    func testResolveRouteInterfaceWithFallback() async throws {
        let runner = ScriptedProcessRunner(
            responses: [
                ScriptedResponse(result: ProcessResult(exitCode: 0, standardOutput: "interface: en0")),
                ScriptedResponse(result: ProcessResult(exitCode: 0, standardOutput: "192.168.1.10\n")),
            ]
        )
        let resolver = HostIPResolver(processRunner: runner)
        let ip = try await resolver.resolveLANIP()

        XCTAssertEqual(ip, "192.168.1.10")
        XCTAssertTrue(runner.calls[0].arguments.prefix(4).contains("route"))
        XCTAssertTrue(runner.calls[1].arguments.prefix(2).contains("ipconfig"))
    }

    func testResolveWithIfconfigFallback() async throws {
        let runner = ScriptedProcessRunner(
            responses: [
                ScriptedResponse(result: ProcessResult(exitCode: 0, standardOutput: "interface: en0")),
                ScriptedResponse(result: ProcessResult(exitCode: 0, standardOutput: "")),
                ScriptedResponse(result: ProcessResult(exitCode: 0, standardOutput: """
                    lo0: flags...
                    inet 127.0.0.1 netmask ...
                    en0: flags...
                    inet 10.0.0.55 netmask ...
                """)),
            ]
        )
        let resolver = HostIPResolver(processRunner: runner)
        let ip = try await resolver.resolveLANIP()

        XCTAssertEqual(ip, "10.0.0.55")
    }

    func testResolveRouteWithoutResultFallsBackToIfconfig() async throws {
        let runner = ScriptedProcessRunner(
            responses: [
                ScriptedResponse(result: ProcessResult(exitCode: 0, standardOutput: "No default route")),
                ScriptedResponse(result: ProcessResult(exitCode: 0, standardOutput: """
                    lo0: flags...
                    inet 127.0.0.1 netmask ...
                    en0: flags...
                    inet 10.10.10.10 netmask ...
                """)),
            ]
        )
        let resolver = HostIPResolver(processRunner: runner)
        let ip = try await resolver.resolveLANIP()

        XCTAssertEqual(ip, "10.10.10.10")
    }
}
