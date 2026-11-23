#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 || -z "$1" ]]; then
  echo "Usage: bash apps/macos/build-app.sh OUTPUT_DIRECTORY" >&2
  exit 2
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Error: build-app.sh must be run on macOS (Darwin)." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="$1"
mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"

APP_BUNDLE="$OUTPUT_DIR/aisubdash.app"
if [[ -e "$APP_BUNDLE" || -L "$APP_BUNDLE" ]]; then
  echo "Error: $APP_BUNDLE already exists. Remove it or specify a clean output directory." >&2
  exit 1
fi

ARCH="$(uname -m)"
PLIST_PATH="$SCRIPT_DIR/Info.plist"
MIN_OS_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$PLIST_PATH")"
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
[[ "$SDK_VERSION" == *.* ]] || SDK_VERSION="$SDK_VERSION.0"

# SwiftPM can record the deployment target as the SDK version, so state both to the linker.
BUILD_ARGS=(
  --package-path "$SCRIPT_DIR"
  -c release
  --arch "$ARCH"
  --product AisubdashMac
  -Xlinker -platform_version -Xlinker macos -Xlinker "$MIN_OS_VERSION" -Xlinker "$SDK_VERSION"
)
swift build "${BUILD_ARGS[@]}"

BIN_DIR="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"
BIN_PATH="$BIN_DIR/AisubdashMac"

if [[ ! -x "$BIN_PATH" ]]; then
  echo "Error: built executable not found at $BIN_PATH" >&2
  exit 1
fi

# macOS selects SwiftUI and AppKit behaviour from the SDK version recorded in the
# executable. With an older recorded SDK the open menu bar panel never shrinks.
RECORDED_SDK="$(otool -l "$BIN_PATH" | awk '/LC_BUILD_VERSION/ { found = 1 } found && $1 == "sdk" { print $2; exit }')"
if [[ "$RECORDED_SDK" != "$SDK_VERSION" ]]; then
  echo "Error: executable records SDK '$RECORDED_SDK', expected the build SDK $SDK_VERSION." >&2
  exit 1
fi

STAGE_DIR="$(mktemp -d "$OUTPUT_DIR/.aisubdash-stage.XXXXXX")"
cleanup() {
  rm -rf "$STAGE_DIR"
}
trap cleanup EXIT

STAGE_APP="$STAGE_DIR/aisubdash.app"
mkdir -p "$STAGE_APP/Contents/MacOS"
install -m 755 "$BIN_PATH" "$STAGE_APP/Contents/MacOS/AisubdashMac"
install -m 644 "$PLIST_PATH" "$STAGE_APP/Contents/Info.plist"

codesign --force --sign - --timestamp=none "$STAGE_APP"
codesign --verify --strict "$STAGE_APP"

mv -n "$STAGE_APP" "$OUTPUT_DIR/"
if [[ -e "$STAGE_APP" ]]; then
  echo "Error: $APP_BUNDLE already exists." >&2
  exit 1
fi
echo "Built and signed $APP_BUNDLE ($ARCH)"
