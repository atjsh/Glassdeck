#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_DEMO_SCRIPT="$ROOT/Scripts/run-animation-demo-sim.sh"
# shellcheck source=Scripts/xcode-test-common.sh
source "$ROOT/Scripts/xcode-test-common.sh"

SIMULATOR_NAME="${SIMULATOR_NAME:-iPhone 17}"
SCREENSHOT_DIR="${SCREENSHOT_DIR:-$ROOT/.build/AnimationDemoVisible}"
FRAME_A_PATH="$SCREENSHOT_DIR/frame-a.png"
FRAME_B_PATH="$SCREENSHOT_DIR/frame-b.png"
RUN_DEMO_ARGS=()
RUN_DEMO_SUPPRESS_OUTPUT=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --clean|--rebuild)
      RUN_DEMO_ARGS+=("$1")
      shift
      ;;
    --verbose)
      RUN_DEMO_ARGS+=("$1")
      RUN_DEMO_SUPPRESS_OUTPUT=0
      shift
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

ensure_xcode_test_tools

mkdir -p "$SCREENSHOT_DIR"

SIMULATOR_ID="$(resolve_simulator_id "$SIMULATOR_NAME")"

if [[ "$RUN_DEMO_SUPPRESS_OUTPUT" == "1" ]]; then
  "$RUN_DEMO_SCRIPT" "${RUN_DEMO_ARGS[@]}" >/dev/null
else
  "$RUN_DEMO_SCRIPT" "${RUN_DEMO_ARGS[@]}"
fi

sleep 4
xcrun simctl io "$SIMULATOR_ID" screenshot "$FRAME_A_PATH" >/dev/null
sleep 1
xcrun simctl io "$SIMULATOR_ID" screenshot "$FRAME_B_PATH" >/dev/null

swift - "$FRAME_A_PATH" "$FRAME_B_PATH" <<'SWIFT'
import CoreGraphics
import Foundation
import ImageIO

struct PixelBuffer {
    let data: CFData
    let width: Int
    let height: Int
    let bytesPerRow: Int
}

func loadBuffer(path: String) throws -> PixelBuffer {
    let url = URL(fileURLWithPath: path)
    guard
        let source = CGImageSourceCreateWithURL(url as CFURL, nil),
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
        let data = image.dataProvider?.data
    else {
        throw NSError(domain: "AnimationDemoVisible", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Failed to decode screenshot at \(path)"
        ])
    }

    return PixelBuffer(
        data: data,
        width: image.width,
        height: image.height,
        bytesPerRow: image.bytesPerRow
    )
}

func pixel(_ buffer: PixelBuffer, x: Int, y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
    let ptr = CFDataGetBytePtr(buffer.data)!
    let offset = (y * buffer.bytesPerRow) + (x * 4)
    return (
        r: Int(ptr[offset]),
        g: Int(ptr[offset + 1]),
        b: Int(ptr[offset + 2]),
        a: Int(ptr[offset + 3])
    )
}

func chromaticPixelCount(in buffer: PixelBuffer, minY: Int) -> Int {
    let step = max(min(buffer.width, buffer.height) / 100, 1)
    var count = 0

    for y in stride(from: minY, to: buffer.height, by: step) {
        for x in stride(from: 0, to: buffer.width, by: step) {
            let p = pixel(buffer, x: x, y: y)
            guard p.a > 12 else { continue }

            let channelDelta = max(
                abs(p.r - p.g),
                abs(p.r - p.b),
                abs(p.g - p.b)
            )
            if channelDelta >= 18 {
                count += 1
            }
        }
    }

    return count
}

func changedPixelCount(first: PixelBuffer, second: PixelBuffer, minY: Int) -> Int {
    let width = min(first.width, second.width)
    let height = min(first.height, second.height)
    let step = max(min(width, height) / 100, 1)
    var count = 0

    for y in stride(from: minY, to: height, by: step) {
        for x in stride(from: 0, to: width, by: step) {
            let a = pixel(first, x: x, y: y)
            let b = pixel(second, x: x, y: y)
            let delta =
                abs(a.r - b.r)
                + abs(a.g - b.g)
                + abs(a.b - b.b)
            if delta >= 24 {
                count += 1
            }
        }
    }

    return count
}

let frameAPath = CommandLine.arguments[1]
let frameBPath = CommandLine.arguments[2]
let frameA = try loadBuffer(path: frameAPath)
let frameB = try loadBuffer(path: frameBPath)
let minY = Int(Double(min(frameA.height, frameB.height)) * 0.18)

let chromaticA = chromaticPixelCount(in: frameA, minY: minY)
let chromaticB = chromaticPixelCount(in: frameB, minY: minY)
let changed = changedPixelCount(first: frameA, second: frameB, minY: minY)

guard chromaticA >= 12 else {
    fputs("Expected the first animation demo screenshot to contain visible chromatic pixels below the navigation chrome; found \(chromaticA).\n", stderr)
    exit(1)
}

guard chromaticB >= 12 else {
    fputs("Expected the second animation demo screenshot to contain visible chromatic pixels below the navigation chrome; found \(chromaticB).\n", stderr)
    exit(1)
}

guard changed >= 20 else {
    fputs("Expected consecutive animation demo screenshots to visibly change; found \(changed) changed sampled pixels.\n", stderr)
    exit(1)
}

print("PASS chromaticA=\(chromaticA) chromaticB=\(chromaticB) changed=\(changed)")
SWIFT

printf 'PASS [test-animation-demo-visible-sim] simulator=%s frame_a=%s frame_b=%s\n' \
  "$SIMULATOR_ID" \
  "$FRAME_A_PATH" \
  "$FRAME_B_PATH"
