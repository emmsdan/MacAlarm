#!/bin/bash
set -e

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
    if [ -f "VERSION" ]; then
        VERSION=$(cat VERSION | tr -d '[:space:]')
    else
        VERSION="1.0.0"
    fi
fi

echo "=== Building MacAlarm Now (v$VERSION) ==="

# 1. Compile in release mode
swift build -c release

# 2. Setup bundle structure
APP_NAME="MacAlarm Now.app"
rm -rf "$APP_NAME"
mkdir -p "$APP_NAME/Contents/MacOS"
mkdir -p "$APP_NAME/Contents/Resources"

# 3. Copy binary
BIN_PATH=$(swift build -c release --show-bin-path)
if [ -f "$BIN_PATH/MacAlarm" ]; then
    echo "✓ Found binary at $BIN_PATH/MacAlarm"
    cp "$BIN_PATH/MacAlarm" "$APP_NAME/Contents/MacOS/MacAlarm"
elif [ -f "$BIN_PATH/Alarm" ]; then
    echo "✓ Found binary at $BIN_PATH/Alarm"
    cp "$BIN_PATH/Alarm" "$APP_NAME/Contents/MacOS/MacAlarm"
elif [ -f ".build/release/MacAlarm" ]; then
    echo "✓ Found binary at .build/release/MacAlarm"
    cp ".build/release/MacAlarm" "$APP_NAME/Contents/MacOS/MacAlarm"
else
    echo "Error: Could not locate built release binary in $BIN_PATH"
    exit 1
fi
chmod +x "$APP_NAME/Contents/MacOS/MacAlarm"

# 3b. Embed .env into App Bundle Resources
if [ -f ".env" ]; then
    cp .env "$APP_NAME/Contents/Resources/.env"
    echo "✓ Embedded build-time .env into $APP_NAME/Contents/Resources/.env"
fi

# 4. Generate Icon
echo "=== Generating App Icons ==="
swift scripts/make_icon.swift
ICONSET_DIR="scripts/AppIcon.iconset"
rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

sips -z 16 16     scripts/icon_1024.png --out "$ICONSET_DIR/icon_16x16.png" > /dev/null
sips -z 32 32     scripts/icon_1024.png --out "$ICONSET_DIR/icon_16x16@2x.png" > /dev/null
sips -z 32 32     scripts/icon_1024.png --out "$ICONSET_DIR/icon_32x32.png" > /dev/null
sips -z 64 64     scripts/icon_1024.png --out "$ICONSET_DIR/icon_32x32@2x.png" > /dev/null
sips -z 128 128   scripts/icon_1024.png --out "$ICONSET_DIR/icon_128x128.png" > /dev/null
sips -z 256 256   scripts/icon_1024.png --out "$ICONSET_DIR/icon_128x128@2x.png" > /dev/null
sips -z 256 256   scripts/icon_1024.png --out "$ICONSET_DIR/icon_256x256.png" > /dev/null
sips -z 512 512   scripts/icon_1024.png --out "$ICONSET_DIR/icon_256x256@2x.png" > /dev/null
sips -z 512 512   scripts/icon_1024.png --out "$ICONSET_DIR/icon_512x512.png" > /dev/null
cp scripts/icon_1024.png "$ICONSET_DIR/icon_512x512@2x.png"

iconutil -c icns "$ICONSET_DIR" -o "$APP_NAME/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET_DIR" scripts/icon_1024.png

# 5. Create Info.plist
cat << EOF > "$APP_NAME/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>MacAlarm</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.hexify.macalarmnow</string>
    <key>CFBundleName</key>
    <string>MacAlarm Now</string>
    <key>CFBundleDisplayName</key>
    <string>MacAlarm Now</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
    <key>NSSpeechSynthesisUsageDescription</key>
    <string>MacAlarm Now uses speech synthesis to sing and announce alarm descriptions loudly.</string>
</dict>
</plist>
EOF

# 6. Ad-hoc code signing
codesign --force --deep --sign - "$APP_NAME"

echo "=== '$APP_NAME' (v$VERSION) successfully created and signed! ==="
