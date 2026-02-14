#!/bin/bash
#
# build-app.sh — Build ScipioManager as a universal macOS .app bundle.
#
# Usage:
#   ./scripts/build-app.sh              Build the .app bundle
#   ./scripts/build-app.sh --install    Build and copy to a target directory
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/.build"
APP_NAME="ScipioManager"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

echo "=== Building $APP_NAME.app ==="

# Step 1: Build for both architectures
echo "[1/4] Building arm64..."
swift build -c release --arch arm64 --package-path "$PROJECT_DIR" 2>&1 | tail -3

echo "[2/4] Building x86_64..."
swift build -c release --arch x86_64 --package-path "$PROJECT_DIR" 2>&1 | tail -3

# Step 3: Create universal binary
echo "[3/4] Creating universal binary..."
ARM64_BIN="$BUILD_DIR/arm64-apple-macosx/release/$APP_NAME"
X86_BIN="$BUILD_DIR/x86_64-apple-macosx/release/$APP_NAME"

if [ ! -f "$ARM64_BIN" ]; then
    echo "ERROR: arm64 binary not found at $ARM64_BIN"
    exit 1
fi
if [ ! -f "$X86_BIN" ]; then
    echo "ERROR: x86_64 binary not found at $X86_BIN"
    exit 1
fi

UNIVERSAL_BIN="$BUILD_DIR/$APP_NAME-universal"
lipo -create "$ARM64_BIN" "$X86_BIN" -output "$UNIVERSAL_BIN"
echo "  Universal binary: $(file "$UNIVERSAL_BIN" | sed 's/.*: //')"

# Step 4: Assemble .app bundle
echo "[4/4] Assembling $APP_NAME.app..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$UNIVERSAL_BIN" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# Copy icon if present
if [ -f "$PROJECT_DIR/Resources/AppIcon.icns" ]; then
    cp "$PROJECT_DIR/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
    echo "  Icon: AppIcon.icns included"
fi

# Write PkgInfo
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

echo ""
echo "=== Build complete ==="
echo "  $APP_BUNDLE"
echo "  Size: $(du -sh "$APP_BUNDLE" | cut -f1)"

# Optional: copy to a target directory
if [ "${1:-}" = "--install" ] && [ -n "${2:-}" ]; then
    INSTALL_DIR="$2"
    echo ""
    echo "Installing to $INSTALL_DIR..."
    rm -rf "$INSTALL_DIR/$APP_NAME.app"
    cp -R "$APP_BUNDLE" "$INSTALL_DIR/"
    echo "  Installed: $INSTALL_DIR/$APP_NAME.app"
fi
