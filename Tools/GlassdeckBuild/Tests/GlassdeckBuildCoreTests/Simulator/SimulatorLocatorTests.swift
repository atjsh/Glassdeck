import XCTest
@testable import GlassdeckBuildCore

final class SimulatorLocatorTests: XCTestCase {
    func testAvailableDevicesParsesSimulatorLines() async throws {
        let fixtureOutput = """
            == Devices ==
              iPhone 15 Pro (AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA) (Shutdown)
              iPhone 17 (BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB) (Shutdown)
        """
        let runner = ScriptedProcessRunner(
            responses: [
                ScriptedResponse(result: ProcessResult(exitCode: 0, standardOutput: fixtureOutput)),
                ScriptedResponse(result: ProcessResult(exitCode: 0, standardOutput: fixtureOutput))
            ]
        )
        let locator = SimulatorLocator(processRunner: runner)
        let devices = try await locator.availableDevices()

        XCTAssertEqual(devices.count, 2)
        XCTAssertEqual(devices.first?.name, "iPhone 15 Pro")
        XCTAssertEqual(devices.last?.identifier, "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")
    }

    func testResolveChoosesExactMatchThenFallbackPrefix() async throws {
        let fixtureOutput = """
            == Devices ==
              iPhone 15 Pro (AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA) (Shutdown)
              iPhone 17 (BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB) (Shutdown)
        """
        let runner = ScriptedProcessRunner(
            responses: [
                ScriptedResponse(result: ProcessResult(exitCode: 0, standardOutput: fixtureOutput)),
                ScriptedResponse(result: ProcessResult(exitCode: 0, standardOutput: fixtureOutput))
            ]
        )

        let locator = SimulatorLocator(processRunner: runner)
        let exact = try await locator.resolve("iPhone 17")
        XCTAssertEqual(exact, "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")

        let fuzzy = try await locator.resolve("iPhone")
        XCTAssertEqual(fuzzy, "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")
    }

    func testResolveUnknownSimulatorFails() async {
        let runner = ScriptedProcessRunner(
            responses: [
                ScriptedResponse(result: ProcessResult(exitCode: 0, standardOutput: "== Devices =="))
            ]
        )
        let locator = SimulatorLocator(processRunner: runner)
        await XCTAssertThrowsErrorAsync {
            _ = try await locator.resolve("nope")
        }
    }
}

extension XCTestCase {
    func XCTAssertThrowsErrorAsync(
        _ expression: @escaping () async throws -> Void,
        _ message: @autoclosure () -> String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await expression()
            XCTFail(message())
        } catch {
        }
    }
}
