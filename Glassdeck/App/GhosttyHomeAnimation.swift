#if canImport(UIKit)
import Foundation
import GlassdeckCore
import QuartzCore
import UIKit

struct GhosttyHomeAnimationProgress: Sendable, Equatable {
    let currentFrame: Int
    let totalFrames: Int

    var accessibilityValue: String {
        "\(currentFrame)/\(totalFrames)"
    }
}

enum GhosttyHomeAnimationError: Error, LocalizedError {
    case framesDirectoryMissing(String)
    case invalidFrameCount(expected: Int, actual: Int)
    case invalidFrameName(String)
    case invalidFrameHeight(file: String, expected: Int, actual: Int)
    case invalidFrameWidth(file: String, line: Int, expected: Int, actual: Int)
    case unsupportedMarkup(file: String, line: Int, snippet: String)
    case unbalancedMarkup(file: String, line: Int)
    case renderFailed(frame: Int, reason: String)

    var errorDescription: String? {
        switch self {
        case .framesDirectoryMissing(let path):
            "Ghostty animation frames directory is missing: \(path)"
        case .invalidFrameCount(let expected, let actual):
            "Expected \(expected) Ghostty animation frames but found \(actual)."
        case .invalidFrameName(let name):
            "Invalid Ghostty animation frame name: \(name)"
        case .invalidFrameHeight(let file, let expected, let actual):
            "Frame \(file) expected \(expected) rows but found \(actual)."
        case .invalidFrameWidth(let file, let line, let expected, let actual):
            "Frame \(file) line \(line) expected \(expected) columns but found \(actual)."
        case .unsupportedMarkup(let file, let line, let snippet):
            "Frame \(file) line \(line) contains unsupported markup near '\(snippet)'."
        case .unbalancedMarkup(let file, let line):
            "Frame \(file) line \(line) contains unbalanced bold markup."
        case .renderFailed(let frame, let reason):
            "Ghostty animation frame \(frame) failed to render: \(reason)"
        }
    }
}

struct GhosttyHomeAnimationSequence {
    struct Frame {
        let payload: Data
        let accentColumnsByRow: [Int: IndexSet]
    }

    static let expectedColumns = 100
    static let expectedRows = 41
    static let expectedFrameCount = 235
    static let startFrameIndex = 16
    static let frameLengthMilliseconds = 31.0
    static let testingTerminalConfiguration = TerminalConfiguration(fontSize: 6)
    static let testingMetricsPreset = GhosttySurfaceMetricsPreset(
        cellSize: CGSize(width: 3.6, height: 9),
        padding: UIEdgeInsets(top: 7, left: 7, bottom: 7, right: 7),
        accentForegroundColor: GhosttyVTColor(r: 0x35, g: 0x51, b: 0xF3)
    )

    private static let accentStartSequence = "\u{1B}[38;2;53;81;243m"
    private static let accentEndSequence = "\u{1B}[39m"

    let frames: [Frame]

    var terminalSize: TerminalSize {
        TerminalSize(columns: Self.expectedColumns, rows: Self.expectedRows)
    }

    static func load(from directory: URL) throws -> Self {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw GhosttyHomeAnimationError.framesDirectoryMissing(directory.path)
        }

        let frameURLs = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        .filter { url in
            url.pathExtension == "txt" && url.lastPathComponent.hasPrefix("frame_")
        }
        .sorted { lhs, rhs in
            do {
                return try Self.frameIndex(for: lhs) < Self.frameIndex(for: rhs)
            } catch {
                return lhs.lastPathComponent < rhs.lastPathComponent
            }
        }

        guard frameURLs.count == Self.expectedFrameCount else {
            throw GhosttyHomeAnimationError.invalidFrameCount(
                expected: Self.expectedFrameCount,
                actual: frameURLs.count
            )
        }

        let frames = try frameURLs.map(Self.normalizedFrame(from:))
        return Self(frames: frames)
    }

    private static func normalizedFrame(from url: URL) throws -> Frame {
        _ = try frameIndex(for: url)
        let rawText = try String(contentsOf: url, encoding: .utf8)
        return try normalizedFrame(
            fromRawText: rawText,
            fileName: url.lastPathComponent
        )
    }

    static func normalizedFramePayload(
        fromRawText rawText: String,
        fileName: String
    ) throws -> Data {
        try normalizedFrame(
            fromRawText: rawText,
            fileName: fileName
        ).payload
    }

    private static func normalizedFrame(
        fromRawText rawText: String,
        fileName: String
    ) throws -> Frame {
        var lines = rawText.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        if lines.last?.isEmpty == true {
            lines.removeLast()
        }

        guard lines.count == Self.expectedRows else {
            throw GhosttyHomeAnimationError.invalidFrameHeight(
                file: fileName,
                expected: Self.expectedRows,
                actual: lines.count
            )
        }

        var payload = "\u{1B}[?25l\u{1B}[H\u{1B}[0m"
        var accentColumnsByRow: [Int: IndexSet] = [:]
        for (index, line) in lines.enumerated() {
            let normalized = try normalizeLine(
                line,
                fileName: fileName,
                lineNumber: index + 1
            )
            payload.append(normalized.payload)
            if !normalized.accentColumns.isEmpty {
                accentColumnsByRow[index] = normalized.accentColumns
            }
            payload.append("\u{1B}[0m")
            if index < lines.count - 1 {
                payload.append("\r\n")
            }
        }

        return Frame(
            payload: Data(payload.utf8),
            accentColumnsByRow: accentColumnsByRow
        )
    }

    private static func normalizeLine(
        _ rawLine: String,
        fileName: String,
        lineNumber: Int
    ) throws -> (payload: String, accentColumns: IndexSet) {
        let openTag = #"<span class="b">"#
        let closeTag = "</span>"

        var visibleColumnCount = 0
        var isAccentOpen = false
        var normalizedLine = ""
        var accentColumns = IndexSet()
        var index = rawLine.startIndex

        while index < rawLine.endIndex {
            let remaining = rawLine[index...]
            if remaining.hasPrefix(openTag) {
                guard !isAccentOpen else {
                    throw GhosttyHomeAnimationError.unbalancedMarkup(file: fileName, line: lineNumber)
                }
                normalizedLine.append("\u{1B}[1m")
                normalizedLine.append(Self.accentStartSequence)
                isAccentOpen = true
                index = rawLine.index(index, offsetBy: openTag.count)
                continue
            }

            if remaining.hasPrefix(closeTag) {
                guard isAccentOpen else {
                    throw GhosttyHomeAnimationError.unbalancedMarkup(file: fileName, line: lineNumber)
                }
                normalizedLine.append("\u{1B}[22m")
                normalizedLine.append(Self.accentEndSequence)
                isAccentOpen = false
                index = rawLine.index(index, offsetBy: closeTag.count)
                continue
            }

            if rawLine[index] == "<" {
                let snippet = String(remaining.prefix(24))
                throw GhosttyHomeAnimationError.unsupportedMarkup(
                    file: fileName,
                    line: lineNumber,
                    snippet: snippet
                )
            }

            normalizedLine.append(rawLine[index])
            if isAccentOpen {
                accentColumns.insert(visibleColumnCount)
            }
            visibleColumnCount += 1
            index = rawLine.index(after: index)
        }

        guard !isAccentOpen else {
            throw GhosttyHomeAnimationError.unbalancedMarkup(file: fileName, line: lineNumber)
        }

        guard visibleColumnCount == Self.expectedColumns else {
            throw GhosttyHomeAnimationError.invalidFrameWidth(
                file: fileName,
                line: lineNumber,
                expected: Self.expectedColumns,
                actual: visibleColumnCount
            )
        }

        return (payload: normalizedLine, accentColumns: accentColumns)
    }

    private static func frameIndex(for url: URL) throws -> Int {
        let stem = url.deletingPathExtension().lastPathComponent
        guard
            stem.hasPrefix("frame_"),
            let index = Int(stem.dropFirst("frame_".count))
        else {
            throw GhosttyHomeAnimationError.invalidFrameName(url.lastPathComponent)
        }
        return index
    }
}

@MainActor
private class WeakDisplayLinkTarget: NSObject {
    private weak var owner: GhosttyHomeAnimationPlayer?
    init(_ owner: GhosttyHomeAnimationPlayer) { self.owner = owner }
    @objc func step(_ link: CADisplayLink) {
        owner?.handleDisplayLink(link)
    }
}

@MainActor
final class GhosttyHomeAnimationPlayer: NSObject {
    struct ReplayMetrics {
        let frameCount: Int
        let totalDuration: TimeInterval

        var averageFrameDuration: TimeInterval {
            totalDuration / Double(max(frameCount, 1))
        }
    }

    let surface: GhosttySurface
    let sequence: GhosttyHomeAnimationSequence

    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?
    private var accumulatedTime: CFTimeInterval = 0
    private var currentFrameIndex = GhosttyHomeAnimationSequence.startFrameIndex

    init(surface: GhosttySurface, sequence: GhosttyHomeAnimationSequence) {
        self.surface = surface
        self.sequence = sequence
        super.init()
    }

    func start() throws {
        guard displayLink == nil else { return }
        try applyCurrentFrame()

        let target = WeakDisplayLinkTarget(self)
        let link = CADisplayLink(target: target, selector: #selector(WeakDisplayLinkTarget.step))
        link.add(to: .main, forMode: .common)
        displayLink = link
        lastTimestamp = nil
        accumulatedTime = 0
    }

    func stop(clearProgress: Bool = true) {
        displayLink?.invalidate()
        displayLink = nil
        lastTimestamp = nil
        accumulatedTime = 0
        surface.setAnimationAccentRows(nil)
        if clearProgress {
            surface.setAnimationProgress(nil)
        }
    }

    func replayLoop() throws -> ReplayMetrics {
        let startTime = CACurrentMediaTime()
        for _ in 0..<sequence.frames.count {
            try applyCurrentFrame()
            advanceFrame()
        }
        return ReplayMetrics(
            frameCount: sequence.frames.count,
            totalDuration: CACurrentMediaTime() - startTime
        )
    }

    @objc
    fileprivate func handleDisplayLink(_ link: CADisplayLink) {
        if let lastTimestamp {
            accumulatedTime += link.timestamp - lastTimestamp
        }
        lastTimestamp = link.timestamp

        let frameTime = GhosttyHomeAnimationSequence.frameLengthMilliseconds / 1_000
        while accumulatedTime >= frameTime {
            accumulatedTime -= frameTime
            advanceFrame()
            do {
                try applyCurrentFrame()
            } catch {
                stop(clearProgress: false)
                surface.setAnimationProgress(
                    GhosttyHomeAnimationProgress(
                        currentFrame: currentFrameIndex,
                        totalFrames: sequence.frames.count
                    )
                )
            }
        }
    }

    private func advanceFrame() {
        currentFrameIndex = (currentFrameIndex + 1) % sequence.frames.count
    }

    private func applyCurrentFrame() throws {
        let frame = sequence.frames[currentFrameIndex]
        surface.setAnimationAccentRows(frame.accentColumnsByRow)
        surface.writeToTerminal(frame.payload)
        surface.setAnimationProgress(
            GhosttyHomeAnimationProgress(
                currentFrame: currentFrameIndex,
                totalFrames: sequence.frames.count
            )
        )

        if let reason = surface.stateSnapshot.renderFailureReason {
            throw GhosttyHomeAnimationError.renderFailed(
                frame: currentFrameIndex,
                reason: reason
            )
        }
    }
}
#endif
