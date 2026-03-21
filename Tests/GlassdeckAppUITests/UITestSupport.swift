import UIKit
import XCTest

struct LiveDockerUITestConfiguration {
    let host: String
    let port: Int
    let username: String
    let password: String
    let privateKeyPath: String

    static func load(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> Self {
        guard environment["GLASSDECK_LIVE_SSH_ENABLED"] == "1" else {
            throw XCTSkip("Set GLASSDECK_LIVE_SSH_ENABLED=1 to run the live Docker UI tests.")
        }

        guard
            let host = environment["GLASSDECK_LIVE_SSH_HOST"],
            let portString = environment["GLASSDECK_LIVE_SSH_PORT"],
            let port = Int(portString),
            let username = environment["GLASSDECK_LIVE_SSH_USER"],
            let password = environment["GLASSDECK_LIVE_SSH_PASSWORD"],
            let privateKeyPath = environment["GLASSDECK_LIVE_SSH_KEY_PATH"]
        else {
            throw XCTSkip("Live Docker UI test environment variables are incomplete.")
        }

        return Self(
            host: host,
            port: port,
            username: username,
            password: password,
            privateKeyPath: privateKeyPath
        )
    }
}

@MainActor
extension XCTestCase {
    private struct ScreenshotAnalysis {
        let effectiveColorCount: Int
        let chromaticSampleCount: Int
        let opaqueSampleCount: Int
        let averageBrightness: Double
    }

    private struct ScreenshotPixelBuffer {
        let data: Data
        let width: Int
        let height: Int
        let bytesPerRow: Int
        let bytesPerPixel: Int
        let alphaOffset: Int
        let colorOffsets: (red: Int, green: Int, blue: Int)
    }

    @discardableResult
    func launchUITestApp(
        scenario: String,
        openActiveSession: Bool = false,
        additionalArguments: [String] = [],
        additionalEnvironment: [String: String] = [:]
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestScenario", scenario, "-uiTestDisableAnimations"]
        if openActiveSession {
            app.launchArguments.append("-uiTestOpenActiveSession")
        }
        app.launchArguments.append(contentsOf: additionalArguments)
        app.launchEnvironment.merge(additionalEnvironment) { _, new in new }
        app.launch()
        return app
    }

    func captureScreenshot(
        named name: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        _ = captureScreenScreenshot(named: name, file: file, line: line)
    }

    @discardableResult
    func captureScreenScreenshot(
        named name: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIScreenshot {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        return screenshot
    }

    @discardableResult
    func captureElementScreenshot(
        of element: XCUIElement,
        named name: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIScreenshot {
        XCTAssertTrue(
            element.waitForExistence(timeout: 10),
            "Expected screenshot target '\(name)' to exist.",
            file: file,
            line: line
        )

        let screenshot = element.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        return screenshot
    }

    func assertScreenshotIsNotBlank(
        of element: XCUIElement,
        named name: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let screenshot = captureElementScreenshot(
            of: element,
            named: name,
            file: file,
            line: line
        )

        guard let buffer = Self.decodeScreenshotPixelBuffer(screenshot) else {
            XCTFail(
                "Failed to decode screenshot for '\(name)'.",
                file: file,
                line: line
            )
            return
        }

        let analysis = Self.analyze(buffer, minimumChannelDelta: 18)
        if analysis.effectiveColorCount > 1 {
            return
        }

        XCTFail(
            "Expected '\(name)' to contain more than one effective color; sampled \(analysis.effectiveColorCount) color from \(analysis.opaqueSampleCount) opaque pixels.",
            file: file,
            line: line
        )
    }

    func assertScreenshotContainsChromaticPixels(
        of element: XCUIElement,
        named name: String,
        minimumChannelDelta: Int = 18,
        minimumChromaticSamples: Int = 3,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let screenshot = captureElementScreenshot(
            of: element,
            named: name,
            file: file,
            line: line
        )

        guard let buffer = Self.decodeScreenshotPixelBuffer(screenshot) else {
            XCTFail(
                "Failed to decode screenshot for '\(name)'.",
                file: file,
                line: line
            )
            return
        }

        let analysis = Self.analyze(buffer, minimumChannelDelta: minimumChannelDelta)
        if analysis.chromaticSampleCount >= minimumChromaticSamples {
            return
        }

        XCTFail(
            "Expected '\(name)' to contain visible chromatic pixels; sampled \(analysis.chromaticSampleCount) chromatic pixels from \(analysis.opaqueSampleCount) opaque samples.",
            file: file,
            line: line
        )
    }

    func assertScreenshotHasAverageBrightness(
        of element: XCUIElement,
        named name: String,
        minimumAverageBrightness: Double,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let screenshot = captureElementScreenshot(
            of: element,
            named: name,
            file: file,
            line: line
        )

        guard let buffer = Self.decodeScreenshotPixelBuffer(screenshot) else {
            XCTFail(
                "Failed to decode screenshot for '\(name)'.",
                file: file,
                line: line
            )
            return
        }

        let analysis = Self.analyze(buffer, minimumChannelDelta: 18)
        XCTAssertGreaterThanOrEqual(
            analysis.averageBrightness,
            minimumAverageBrightness,
            "Expected '\(name)' to be visibly light; sampled average brightness \(analysis.averageBrightness).",
            file: file,
            line: line
        )
    }

    func assertScreenshotsDiffer(
        _ first: XCUIScreenshot,
        _ second: XCUIScreenshot,
        named name: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard
            let firstBuffer = Self.decodeScreenshotPixelBuffer(first),
            let secondBuffer = Self.decodeScreenshotPixelBuffer(second)
        else {
            XCTFail(
                "Failed to decode screenshots for '\(name)'.",
                file: file,
                line: line
            )
            return
        }

        let areIdentical =
            firstBuffer.width == secondBuffer.width
            && firstBuffer.height == secondBuffer.height
            && firstBuffer.bytesPerRow == secondBuffer.bytesPerRow
            && firstBuffer.bytesPerPixel == secondBuffer.bytesPerPixel
            && firstBuffer.data == secondBuffer.data

        XCTAssertFalse(
            areIdentical,
            "Expected '\(name)' to visibly change between captured frames.",
            file: file,
            line: line
        )
    }

    func waitForTerminalRenderSummary(
        containing marker: String,
        in app: XCUIApplication,
        timeout: TimeInterval = 20,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let summaryElement = app.descendants(matching: .any)
            .matching(identifier: "terminal-render-summary")
            .firstMatch
        XCTAssertTrue(
            summaryElement.waitForExistence(timeout: 10),
            "Expected the terminal render summary accessibility element to exist.",
            file: file,
            line: line
        )

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let summary = (summaryElement.value as? String) ?? summaryElement.label
            if summary.contains(marker) {
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }

        let currentSummary = (summaryElement.value as? String) ?? summaryElement.label
        XCTFail(
            "Timed out waiting for terminal render summary to contain '\(marker)'. Current summary: \(currentSummary)",
            file: file,
            line: line
        )
    }

    func waitForTerminalRenderSummary(
        containingAnyOf markers: [String],
        in app: XCUIApplication,
        timeout: TimeInterval = 20,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertFalse(markers.isEmpty, "Expected at least one terminal marker to wait for.", file: file, line: line)

        let summaryElement = app.descendants(matching: .any)
            .matching(identifier: "terminal-render-summary")
            .firstMatch
        XCTAssertTrue(
            summaryElement.waitForExistence(timeout: 10),
            "Expected the terminal render summary accessibility element to exist.",
            file: file,
            line: line
        )

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let summary = (summaryElement.value as? String) ?? summaryElement.label
            if markers.contains(where: summary.contains) {
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }

        let currentSummary = (summaryElement.value as? String) ?? summaryElement.label
        XCTFail(
            "Timed out waiting for terminal render summary to contain any of: \(markers). Current summary: \(currentSummary)",
            file: file,
            line: line
        )
    }

    @discardableResult
    func waitForAnimationProgress(
        pastFrame frame: Int,
        in app: XCUIApplication,
        timeout: TimeInterval = 10,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Int {
        let progressElement = app.descendants(matching: .any)
            .matching(identifier: "terminal-animation-progress")
            .firstMatch
        XCTAssertTrue(
            progressElement.waitForExistence(timeout: 10),
            "Expected the terminal animation progress accessibility element to exist.",
            file: file,
            line: line
        )

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let progressValue = (progressElement.value as? String) ?? progressElement.label
            if let currentFrame = Self.animationFrameIndex(from: progressValue), currentFrame > frame {
                return currentFrame
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        let currentValue = (progressElement.value as? String) ?? progressElement.label
        XCTFail(
            "Timed out waiting for terminal animation progress to advance past frame \(frame). Current progress: \(currentValue)",
            file: file,
            line: line
        )
        return Self.animationFrameIndex(from: currentValue) ?? frame
    }

    func currentAnimationFrame(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Int {
        let progressElement = app.descendants(matching: .any)
            .matching(identifier: "terminal-animation-progress")
            .firstMatch
        XCTAssertTrue(
            progressElement.waitForExistence(timeout: 10),
            "Expected the terminal animation progress accessibility element to exist.",
            file: file,
            line: line
        )

        let progressValue = (progressElement.value as? String) ?? progressElement.label
        guard let currentFrame = Self.animationFrameIndex(from: progressValue) else {
            XCTFail(
                "Expected a parseable terminal animation progress value. Current progress: \(progressValue)",
                file: file,
                line: line
            )
            return 0
        }

        return currentFrame
    }

    func replaceText(
        in element: XCUIElement,
        with text: String,
        deleteCount: Int = 0,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(element.waitForExistence(timeout: 5), "Expected input element to exist.", file: file, line: line)
        element.tap()
        if deleteCount > 0 {
            element.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: deleteCount))
        }
        element.typeText(text)
    }

    func connectionRowIdentifier(name: String, host: String) -> String {
        "connection-row-\(accessibilitySlug(name))-\(accessibilitySlug(host))"
    }

    func requireScreenshotCaptureEnabled(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws {
        guard environment["GLASSDECK_UI_SCREENSHOT_CAPTURE"] == "1" else {
            throw XCTSkip("Set GLASSDECK_UI_SCREENSHOT_CAPTURE=1 to run screenshot-only UI tests.")
        }
    }

    func homeAnimationFramesPath(
        file: StaticString = #filePath
    ) -> String {
        let sourceURL = URL(fileURLWithPath: "\(file)")
        return sourceURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Tests/Fixtures/GhosttyHomeAnimationFrames")
            .path()
    }

    private func accessibilitySlug(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private static func alphaComponentOffset(
        alphaInfo: CGImageAlphaInfo,
        bytesPerPixel: Int
    ) -> Int? {
        switch alphaInfo {
        case .premultipliedFirst, .first, .noneSkipFirst:
            return 0
        case .premultipliedLast, .last, .noneSkipLast:
            return bytesPerPixel - 1
        default:
            return nil
        }
    }

    private static func colorComponentOffsets(
        alphaInfo: CGImageAlphaInfo,
        bytesPerPixel: Int
    ) -> (red: Int, green: Int, blue: Int)? {
        guard bytesPerPixel >= 4 else { return nil }

        switch alphaInfo {
        case .premultipliedFirst, .first, .noneSkipFirst:
            return (red: 1, green: 2, blue: 3)
        case .premultipliedLast, .last, .noneSkipLast:
            return (red: 0, green: 1, blue: 2)
        default:
            return nil
        }
    }

    private static func animationFrameIndex(from progressValue: String) -> Int? {
        Int(progressValue.split(separator: "/").first ?? "")
    }

    private static func analyze(
        _ buffer: ScreenshotPixelBuffer,
        minimumChannelDelta: Int
    ) -> ScreenshotAnalysis {
        let step = max(min(buffer.width, buffer.height) / 80, 1)
        var sampledColors = Set<UInt32>()
        var chromaticSampleCount = 0
        var opaqueSampleCount = 0
        var totalBrightness = 0.0

        for y in stride(from: 0, to: buffer.height, by: step) {
            for x in stride(from: 0, to: buffer.width, by: step) {
                let pixelOffset = (y * buffer.bytesPerRow) + (x * buffer.bytesPerPixel)
                let alpha = Int(buffer.data[pixelOffset + buffer.alphaOffset])
                guard alpha > 12 else { continue }

                let red = UInt32(buffer.data[pixelOffset + buffer.colorOffsets.red])
                let green = UInt32(buffer.data[pixelOffset + buffer.colorOffsets.green])
                let blue = UInt32(buffer.data[pixelOffset + buffer.colorOffsets.blue])
                let quantizedColor = ((red / 16) << 8) | ((green / 16) << 4) | (blue / 16)

                sampledColors.insert(quantizedColor)
                opaqueSampleCount += 1
                totalBrightness += (0.2126 * Double(red)) + (0.7152 * Double(green)) + (0.0722 * Double(blue))

                let channelDelta = Int(max(red, green, blue) - min(red, green, blue))
                if channelDelta >= minimumChannelDelta {
                    chromaticSampleCount += 1
                }
            }
        }

        return ScreenshotAnalysis(
            effectiveColorCount: sampledColors.count,
            chromaticSampleCount: chromaticSampleCount,
            opaqueSampleCount: opaqueSampleCount,
            averageBrightness: opaqueSampleCount > 0 ? totalBrightness / Double(opaqueSampleCount) : 0
        )
    }

    private static func decodeScreenshotPixelBuffer(
        _ screenshot: XCUIScreenshot
    ) -> ScreenshotPixelBuffer? {
        guard
            let image = UIImage(data: screenshot.pngRepresentation),
            let cgImage = image.cgImage,
            let dataProvider = cgImage.dataProvider,
            let pixelData = dataProvider.data
        else {
            return nil
        }

        let bitsPerPixel = cgImage.bitsPerPixel
        let bytesPerPixel = max(bitsPerPixel / 8, 1)
        let alphaInfo = cgImage.alphaInfo
        guard
            let alphaOffset = alphaComponentOffset(
                alphaInfo: alphaInfo,
                bytesPerPixel: bytesPerPixel
            ),
            let colorOffsets = colorComponentOffsets(
                alphaInfo: alphaInfo,
                bytesPerPixel: bytesPerPixel
            )
        else {
            return nil
        }

        return ScreenshotPixelBuffer(
            data: pixelData as Data,
            width: cgImage.width,
            height: cgImage.height,
            bytesPerRow: cgImage.bytesPerRow,
            bytesPerPixel: bytesPerPixel,
            alphaOffset: alphaOffset,
            colorOffsets: colorOffsets
        )
    }

}
