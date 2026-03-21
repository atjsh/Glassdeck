#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT/GlassdeckApp.xcodeproj"
PROJECT_FILE="$PROJECT/project.pbxproj"
PATCH_SCRIPT="$ROOT/Scripts/patch-local-package-product.py"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen is required to generate $PROJECT." >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required to patch $PROJECT_FILE." >&2
  exit 1
fi

(
  cd "$ROOT"
  xcodegen generate
)

python3 "$PATCH_SCRIPT" "$PROJECT_FILE"

if ! grep -q 'package = .*XCLocalSwiftPackageReference "Vendor/swift-ssh-client"' "$PROJECT_FILE"; then
  echo "Failed to verify SSHClient local package patch in $PROJECT_FILE." >&2
  exit 1
fi

echo "Generated and patched $PROJECT_FILE"
