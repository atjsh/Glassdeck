import XCTest
@testable import GlassdeckBuildCore

final class SimulatorBootTests: XCTestCase {
    func testBootInvocationChainRespectsOpenFlag() {
        let boot = SimulatorBoot(simctlExecutable: "/usr/bin/xcrun", openExecutable: "/usr/bin/open")
        let withLauncher = try? boot.bootInvocationChain(simulatorIdentifier: "SIM123", openSimulator: true)
        let withoutLauncher = try? boot.bootInvocationChain(simulatorIdentifier: "SIM123", openSimulator: false)

        XCTAssertNotNil(withLauncher)
        XCTAssertNotNil(withoutLauncher)
        XCTAssertEqual(withLauncher?.count, 3)
        XCTAssertEqual(withoutLauncher?.count, 2)
        XCTAssertEqual(withLauncher?[0].arguments, ["-a", "Simulator"])
        XCTAssertEqual(withLauncher?[0].executable, "/usr/bin/open")
        XCTAssertEqual(withoutLauncher?.first?.executable, "/usr/bin/xcrun")
    }

    func testBootIgnoresAlreadyBootedErrorAndContinues() async {
        let runner = ScriptedProcessRunner(
            responses: [
                ScriptedResponse(result: ProcessResult(exitCode: 0)),
                ScriptedResponse(
                    result: ProcessResult(exitCode: 0),
                    error: ProcessRunnerError.nonzeroExit(
                        ProcessResult(
                            exitCode: 255,
                            standardOutput: "Current state: Booted"
                        )
                    )
                ),
                ScriptedResponse(result: ProcessResult(exitCode: 0)),
            ]
        )
        let boot = SimulatorBoot(processRunner: runner, simctlExecutable: "/usr/bin/env")
        try? await boot.boot(simulatorIdentifier: "SIM123")

        XCTAssertEqual(runner.calls.count, 3)
        XCTAssertEqual(runner.calls[1].arguments, ["xcrun", "simctl", "boot", "SIM123"])
        XCTAssertEqual(runner.calls[2].arguments, ["xcrun", "simctl", "bootstatus", "SIM123", "-b"])
    }

    func testBootPropagatesNonBootInvocationErrors() async {
        let runner = ScriptedProcessRunner(
            responses: [
                ScriptedResponse(
                    result: ProcessResult(exitCode: 255),
                    error: ProcessRunnerError.nonzeroExit(
                        ProcessResult(exitCode: 255, standardError: "panic")
                    )
                ),
            ]
        )
        let boot = SimulatorBoot(processRunner: runner, simctlExecutable: "/usr/bin/env")

        await XCTAssertThrowsErrorAsync {
            try await boot.boot(simulatorIdentifier: "SIM123")
        }
    }
}
