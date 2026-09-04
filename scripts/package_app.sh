#!/usr/bin/env bash
set -euo pipefail

# SwarmDeck macOS App Packaging Script
# Packages a standalone, codesigned SwarmDeck.app bundle

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

CONFIGURATION="release"
TARGET="SwarmDeck"
SIGN_IDENTITY="-"
CREATE_ZIP=false
CREATE_DMG=false
OUTPUT_DIR=""

print_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  -c, --configuration <debug|release>  Build configuration (default: release)
  -t, --target <name>                 Target product to package (default: SwarmDeck)
  -o, --output <dir>                  Output directory (default: build/<Configuration>)
  -s, --sign-identity <id>            Codesign identity (default: '-' for ad-hoc)
      --zip                           Create a distributable .zip archive
      --dmg                           Create a distributable .dmg disk image
  -h, --help                          Show this help message

Examples:
  ./scripts/package_app.sh
  ./scripts/package_app.sh --configuration debug
  ./scripts/package_app.sh --zip --dmg
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -c|--configuration)
            CONFIGURATION="$2"
            shift 2
            ;;
        -t|--target)
            TARGET="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -s|--sign-identity)
            SIGN_IDENTITY="$2"
            shift 2
            ;;
        --zip)
            CREATE_ZIP=true
            shift
            ;;
        --dmg)
            CREATE_DMG=true
            shift
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        *)
            echo "Error: Unknown argument '$1'" >&2
            print_usage
            exit 1
            ;;
    esac
done

if [[ -z "$OUTPUT_DIR" ]]; then
    if [[ "$CONFIGURATION" == "release" ]]; then
        CONFIG_NAME="Release"
    else
        CONFIG_NAME="Debug"
    fi
    OUTPUT_DIR="$ROOT_DIR/build/$CONFIG_NAME"
fi

echo "================================================================="
echo " SwarmDeck macOS App Packaging"
echo " Configuration: $CONFIGURATION"
echo " Target:        $TARGET"
echo " Output Dir:    $OUTPUT_DIR"
echo " Sign Identity: $SIGN_IDENTITY"
echo "================================================================="

cd "$ROOT_DIR"

# 1. Compile target using Swift Package Manager
echo "==> Building $TARGET ($CONFIGURATION)..."
swift build -c "$CONFIGURATION" --product "$TARGET"

BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"
EXECUTABLE_PATH="$BIN_DIR/$TARGET"

if [[ ! -f "$EXECUTABLE_PATH" ]]; then
    echo "Error: Executable not found at $EXECUTABLE_PATH" >&2
    exit 1
fi

# 2. Check and regenerate AppIcon.icns if missing
if [[ ! -f "Resources/AppIcon.icns" ]]; then
    echo "==> Generating AppIcon.icns..."
    swift scripts/generate_icon.swift
fi

# 3. Create bundle skeleton
APP_NAME="$TARGET.app"
APP_DIR="$OUTPUT_DIR/$APP_NAME"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "==> Assembling $APP_NAME bundle..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Copy binary
cp "$EXECUTABLE_PATH" "$MACOS_DIR/$TARGET"
chmod +x "$MACOS_DIR/$TARGET"

# Copy Info.plist
if [[ -f "Resources/Info.plist" ]]; then
    cp "Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
else
    echo "Error: Resources/Info.plist not found" >&2
    exit 1
fi

# Update executable name in Info.plist if packaging a different target
if [[ "$TARGET" != "SwarmDeck" ]]; then
    plutil -replace CFBundleExecutable -string "$TARGET" "$CONTENTS_DIR/Info.plist"
    plutil -replace CFBundleName -string "$TARGET" "$CONTENTS_DIR/Info.plist"
fi

# Copy App Icon
if [[ -f "Resources/AppIcon.icns" ]]; then
    cp "Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi

# Copy Ghostty terminal resource bundle if present
GHOSTTY_BUNDLE="$BIN_DIR/GhosttyKit_GhosttyTerminal.bundle"
if [[ -d "$GHOSTTY_BUNDLE" ]]; then
    echo "==> Bundling GhosttyKit resources and terminfo..."
    cp -R "$GHOSTTY_BUNDLE" "$RESOURCES_DIR/"
    
    # Ensure resource bundle has an Info.plist for valid CFBundle signing
    if [[ ! -f "$RESOURCES_DIR/GhosttyKit_GhosttyTerminal.bundle/Info.plist" ]]; then
        cat << 'BUNDLE_PLIST' > "$RESOURCES_DIR/GhosttyKit_GhosttyTerminal.bundle/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.rafaelscharf.SwarmDeck.ghostty-resources</string>
    <key>CFBundleName</key>
    <string>GhosttyKit_GhosttyTerminal</string>
    <key>CFBundlePackageType</key>
    <string>BNDL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
</dict>
</plist>
BUNDLE_PLIST
    fi
fi

# Copy dSYM if present for symbolication
DSYM_PATH="$BIN_DIR/$TARGET.dSYM"
if [[ -d "$DSYM_PATH" ]]; then
    echo "==> Preserving dSYM debug symbols..."
    rm -rf "$OUTPUT_DIR/$TARGET.dSYM"
    cp -R "$DSYM_PATH" "$OUTPUT_DIR/"
fi

# 4. Code signing
ENTITLEMENTS_FILE="$ROOT_DIR/Resources/SwarmDeck.entitlements"
echo "==> Signing $APP_NAME with identity '$SIGN_IDENTITY'..."

# Sign nested bundle first if present
if [[ -d "$RESOURCES_DIR/GhosttyKit_GhosttyTerminal.bundle" ]]; then
    codesign --force --sign "$SIGN_IDENTITY" --timestamp=none "$RESOURCES_DIR/GhosttyKit_GhosttyTerminal.bundle"
fi

# Sign main bundle with entitlements
if [[ -f "$ENTITLEMENTS_FILE" ]]; then
    codesign --force --deep --sign "$SIGN_IDENTITY" --entitlements "$ENTITLEMENTS_FILE" --timestamp=none "$APP_DIR"
else
    codesign --force --deep --sign "$SIGN_IDENTITY" --timestamp=none "$APP_DIR"
fi

# 5. Verification
echo "==> Verifying signature and bundle integrity..."
codesign --verify --deep --strict --verbose=2 "$APP_DIR"
plutil -lint "$CONTENTS_DIR/Info.plist"

APP_SIZE="$(du -sh "$APP_DIR" | cut -f1)"
ARCH_INFO="$(lipo -archs "$MACOS_DIR/$TARGET" 2>/dev/null || file "$MACOS_DIR/$TARGET" | cut -d: -f2)"

echo "✓ Bundle successfully created!"
echo "  Path:         $APP_DIR"
echo "  Size:         $APP_SIZE"
echo "  Architecture: $ARCH_INFO"

# 6. Optional packaging (ZIP / DMG)
if [[ "$CREATE_ZIP" == true ]]; then
    ZIP_PATH="$OUTPUT_DIR/$TARGET.zip"
    echo "==> Creating distributable ZIP: $ZIP_PATH..."
    rm -f "$ZIP_PATH"
    (cd "$OUTPUT_DIR" && ditto -c -k --sequesterRsrc --keepParent "$APP_NAME" "$TARGET.zip")
    echo "✓ Created $(basename "$ZIP_PATH") ($(du -sh "$ZIP_PATH" | cut -f1))"
fi

if [[ "$CREATE_DMG" == true ]]; then
    DMG_PATH="$OUTPUT_DIR/$TARGET.dmg"
    echo "==> Creating distributable DMG: $DMG_PATH..."
    rm -f "$DMG_PATH"
    hdiutil create -volname "$TARGET" -srcfolder "$APP_DIR" -ov -format UDZO "$DMG_PATH" > /dev/null
    echo "✓ Created $(basename "$DMG_PATH") ($(du -sh "$DMG_PATH" | cut -f1))"
fi

echo "================================================================="
echo " Done! Launch with: open "$APP_DIR""
echo "================================================================="
