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

APP_NAME="MacAlarm Now.app"
DMG_NAME="MacAlarm-${VERSION}.dmg"
VOL_NAME="MacAlarm Now"
STAGING_DIR="dmg_staging"
TMP_DMG="temp_$DMG_NAME"

echo "=== Preparing DMG Build for $DMG_NAME ==="

# 1. Ensure MacAlarm Now.app exists
if [ ! -d "$APP_NAME" ]; then
    echo "$APP_NAME not found. Building first..."
    ./scripts/bundle_app.sh "$VERSION"
fi

# 2. Generate DMG Background
echo "=== Generating DMG Background Graphic ==="
swift scripts/make_dmg_background.swift

# 3. Clean up old staging artifacts
rm -rf "$STAGING_DIR" "$TMP_DMG" "$DMG_NAME"
mkdir -p "$STAGING_DIR"

# 4. Copy App and create Applications symlink
echo "=== Staging files ==="
cp -R "$APP_NAME" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

# Hidden background folder
mkdir -p "$STAGING_DIR/.background"
cp scripts/dmg_background.png "$STAGING_DIR/.background/background.png"
rm -f scripts/dmg_background.png

# 5. Calculate required size in MB
APP_SIZE=$(du -sk "$STAGING_DIR" | awk '{print $1}')
DMG_SIZE=$(( (APP_SIZE / 1024) + 30 )) # Add 30MB overhead

echo "Creating temporary writable DMG of size ${DMG_SIZE}MB..."
hdiutil create -srcfolder "$STAGING_DIR" -volname "$VOL_NAME" -fs HFS+ \
    -fsargs "-c c=64,a=16,e=16" -format UDRW -size ${DMG_SIZE}m "$TMP_DMG"

# 6. Mount the DMG
echo "Mounting temporary image..."
MOUNT_DIR=$(hdiutil attach -readwrite -noverify -noautoopen "$TMP_DMG" | egrep '^/dev/' | sed 1q | awk '{print $3}')
if [ -z "$MOUNT_DIR" ]; then
    MOUNT_DIR="/Volumes/$VOL_NAME"
fi

# 7. Customize view via AppleScript
echo "Configuring Finder view layout..."
sleep 2

osascript << EOF || true
tell application "Finder"
    tell disk "$VOL_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {300, 150, 960, 570}
        set theViewOptions to the icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 110
        try
            set background picture of theViewOptions to file ".background:background.png"
        end try
        set position of item "$APP_NAME" of container window to {160, 240}
        set position of item "Applications" of container window to {500, 240}
        close
        open
        update without registering applications
        delay 1
    end tell
end tell
EOF

sync
sleep 2

# 8. Unmount
echo "Unmounting volume..."
hdiutil detach "$MOUNT_DIR" -force || true
sleep 3

# 9. Compress to final distribution DMG
echo "=== Compressing to Final UDZO DMG: $DMG_NAME ==="
rm -f "$DMG_NAME"

CONVERT_SUCCESS=false
for i in 1 2 3 4 5; do
    if hdiutil convert "$TMP_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG_NAME"; then
        CONVERT_SUCCESS=true
        break
    else
        echo "Waiting for disk resource to become available (attempt $i/5)..."
        sleep 2
    fi
done

if [ "$CONVERT_SUCCESS" = false ]; then
    echo "Error: Failed to convert DMG after multiple attempts."
    exit 1
fi

# 10. Clean up
rm -rf "$STAGING_DIR" "$TMP_DMG"

echo "=== SUCCESS: $DMG_NAME created successfully! ==="
ls -lh "$DMG_NAME"
