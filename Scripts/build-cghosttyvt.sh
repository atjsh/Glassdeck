#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_GHOSTTY_ROOT="$(cd "$ROOT/../ghostty-org/ghostty" 2>/dev/null && pwd || true)"

GHOSTTY_ROOT="${GHOSTTY_ROOT:-$DEFAULT_GHOSTTY_ROOT}"
ZIG_BIN="${ZIG_BIN:-$(command -v zig || true)}"
BUILD_ROOT="${BUILD_ROOT:-$ROOT/.build/cghosttyvt}"
OUTPUT_XCFRAMEWORK="${OUTPUT_XCFRAMEWORK:-$ROOT/Frameworks/CGhosttyVT.xcframework}"
OPTIMIZE="${OPTIMIZE:-ReleaseFast}"
DEVICE_TARGET="${DEVICE_TARGET:-aarch64-ios}"
SIMULATOR_ARM64_TARGET="${SIMULATOR_ARM64_TARGET:-aarch64-ios-simulator}"
SIMULATOR_ARM64_CPU="${SIMULATOR_ARM64_CPU:-apple_a17}"
INCLUDE_X86_64_SIMULATOR="${INCLUDE_X86_64_SIMULATOR:-false}"
SIMULATOR_X86_64_TARGET="${SIMULATOR_X86_64_TARGET:-x86_64-ios-simulator}"
MODULE_NAME="${MODULE_NAME:-CGhosttyVT}"
SIMD_ENABLED="${SIMD_ENABLED:-false}"
LIBRARY_BASENAME="libghostty-vt.a"

require_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "error: required command not found: $1" >&2
        exit 1
    fi
}

build_slice() {
    local name="$1"
    local target="$2"
    shift 2

    local prefix="$BUILD_ROOT/$name/prefix"
    local local_cache="$BUILD_ROOT/$name/local-cache"
    local global_cache="$BUILD_ROOT/$name/global-cache"

    mkdir -p "$prefix" "$local_cache" "$global_cache"

    (
        cd "$GHOSTTY_ROOT"
        env \
            ZIG_LOCAL_CACHE_DIR="$local_cache" \
            ZIG_GLOBAL_CACHE_DIR="$global_cache" \
            "$ZIG_BIN" build \
            --build-file "$STATIC_BUILD_FILE" \
            install \
            "-Dtarget=$target" \
            "-Doptimize=$OPTIMIZE" \
            "-Dsimd=$SIMD_ENABLED" \
            "$@" \
            --prefix "$prefix"
    )
}

stage_public_headers() {
    local source_prefix="$1"
    local headers_dir="$BUILD_ROOT/headers"

    rm -rf "$headers_dir"
    mkdir -p "$headers_dir/ghostty"
    ditto "$source_prefix/include/ghostty" "$headers_dir/ghostty"
    find "$headers_dir" -name .DS_Store -delete 2>/dev/null || true

    cat > "$headers_dir/${MODULE_NAME}.h" <<'EOF'
#pragma once
#include <ghostty/vt.h>
EOF

    cat > "$headers_dir/module.modulemap" <<'EOF'
module CGhosttyVT {
  umbrella header "CGhosttyVT.h"
  export *
  module * { export * }
}
EOF

    echo "$headers_dir"
}

copy_library() {
    local source_prefix="$1"
    local destination="$2"

    mkdir -p "$(dirname "$destination")"
    cp "$source_prefix/lib/$LIBRARY_BASENAME" "$destination"
}

package_xcframework() {
    local device_library="$1"
    local simulator_library="$2"
    local headers_dir="$3"

    mkdir -p "$(dirname "$OUTPUT_XCFRAMEWORK")"

    if [ -e "$OUTPUT_XCFRAMEWORK" ]; then
        local backup="$BUILD_ROOT/$(basename "$OUTPUT_XCFRAMEWORK").backup.$(date +%Y%m%d%H%M%S)"
        mv "$OUTPUT_XCFRAMEWORK" "$backup"
        echo "moved existing xcframework to $backup"
    fi

    xcodebuild -create-xcframework \
        -library "$device_library" \
        -headers "$headers_dir" \
        -library "$simulator_library" \
        -headers "$headers_dir" \
        -output "$OUTPUT_XCFRAMEWORK"

    find "$OUTPUT_XCFRAMEWORK" -name .DS_Store -delete 2>/dev/null || true
}

verify_xcframework() {
    local device_library="$OUTPUT_XCFRAMEWORK/ios-arm64/$LIBRARY_BASENAME"
    local simulator_library="$OUTPUT_XCFRAMEWORK/ios-arm64-simulator/$LIBRARY_BASENAME"

    if [ ! -f "$device_library" ] || [ ! -f "$simulator_library" ]; then
        echo "error: xcframework does not contain expected static libraries." >&2
        exit 1
    fi

    xcrun lipo -info "$device_library" >/dev/null
    xcrun lipo -info "$simulator_library" >/dev/null
}

require_cmd xcodebuild
require_cmd ditto
require_cmd xcrun

if [ -z "$ZIG_BIN" ]; then
    echo "error: zig 0.15.2+ is required but was not found on PATH" >&2
    exit 1
fi

if [ ! -d "$GHOSTTY_ROOT" ]; then
    echo "error: Ghostty checkout not found at $GHOSTTY_ROOT" >&2
    echo "set GHOSTTY_ROOT=/absolute/path/to/ghostty before running this script" >&2
    exit 1
fi

if [ "$SIMD_ENABLED" != "false" ]; then
    echo "error: SIMD-enabled static CGhosttyVT packaging is not supported yet; use SIMD_ENABLED=false" >&2
    exit 1
fi

mkdir -p "$BUILD_ROOT"

STATIC_BUILD_FILE="$GHOSTTY_ROOT/.glassdeck-build-static-vt.zig"
trap 'rm -f "$STATIC_BUILD_FILE"' EXIT

cat > "$STATIC_BUILD_FILE" <<'EOF'
const std = @import("std");
const buildpkg = @import("src/build/main.zig");
const appVersion = @import("build.zig.zon").version;
const minimumZigVersion = @import("build.zig.zon").minimum_zig_version;

comptime {
    buildpkg.requireZig(minimumZigVersion);
}

pub fn build(b: *std.Build) !void {
    const config = try buildpkg.Config.init(b, appVersion);
    const deps = try buildpkg.SharedDeps.init(b, &config);
    const mod = try buildpkg.GhosttyZig.init(b, &config, &deps);

    const obj = b.addObject(.{
        .name = "ghostty-vt",
        .root_module = mod.vt_c,
        .use_llvm = true,
    });
    obj.bundle_compiler_rt = true;
    obj.bundle_ubsan_rt = true;

    var sources = [_]std.Build.LazyPath{obj.getEmittedBin()};
    const libtool = buildpkg.LibtoolStep.create(b, .{
        .name = "ghostty-vt",
        .out_name = "libghostty-vt-fat.a",
        .sources = sources[0..],
    });
    libtool.step.dependOn(&obj.step);

    const install_lib = b.addInstallLibFile(libtool.output, "libghostty-vt.a");
    const install_hdr = b.addInstallDirectory(.{
        .source_dir = b.path("include/ghostty"),
        .install_dir = .header,
        .install_subdir = "ghostty",
        .include_extensions = &.{ ".h" },
    });
    b.getInstallStep().dependOn(&install_lib.step);
    b.getInstallStep().dependOn(&install_hdr.step);
}
EOF

build_slice device "$DEVICE_TARGET"
build_slice simulator-arm64 "$SIMULATOR_ARM64_TARGET" "-Dcpu=$SIMULATOR_ARM64_CPU"

device_prefix="$BUILD_ROOT/device/prefix"
sim_arm64_prefix="$BUILD_ROOT/simulator-arm64/prefix"
device_library="$BUILD_ROOT/device/$LIBRARY_BASENAME"
simulator_library="$BUILD_ROOT/simulator-arm64/$LIBRARY_BASENAME"

copy_library "$device_prefix" "$device_library"
copy_library "$sim_arm64_prefix" "$simulator_library"

if [ "$INCLUDE_X86_64_SIMULATOR" = "true" ]; then
    build_slice simulator-x86_64 "$SIMULATOR_X86_64_TARGET"
    sim_x86_64_prefix="$BUILD_ROOT/simulator-x86_64/prefix"
    simulator_universal="$BUILD_ROOT/libghostty-vt-ios-simulator.a"
    xcrun lipo \
        -create \
        "$sim_arm64_prefix/lib/$LIBRARY_BASENAME" \
        "$sim_x86_64_prefix/lib/$LIBRARY_BASENAME" \
        -output "$simulator_universal"
    simulator_library="$simulator_universal"
fi

headers_dir="$(stage_public_headers "$device_prefix")"
package_xcframework "$device_library" "$simulator_library" "$headers_dir"
verify_xcframework

echo "built $OUTPUT_XCFRAMEWORK"
