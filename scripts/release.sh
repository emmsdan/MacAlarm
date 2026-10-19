#!/bin/bash
set -e

VERSION_FILE="VERSION"

# 1. Read current version
if [ -f "$VERSION_FILE" ]; then
    CURRENT_VERSION=$(cat "$VERSION_FILE" | tr -d '[:space:]')
else
    CURRENT_VERSION="1.0.0"
fi

# 2. Determine bump type or target version
BUMP_TYPE="${1:-patch}"

IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"
MAJOR=${MAJOR:-1}
MINOR=${MINOR:-0}
PATCH=${PATCH:-0}

case "$BUMP_TYPE" in
    patch|"")
        NEW_PATCH=$((PATCH + 1))
        NEW_VERSION="${MAJOR}.${MINOR}.${NEW_PATCH}"
        ;;
    minor)
        NEW_MINOR=$((MINOR + 1))
        NEW_VERSION="${MAJOR}.${NEW_MINOR}.0"
        ;;
    major)
        NEW_MAJOR=$((MAJOR + 1))
        NEW_VERSION="${NEW_MAJOR}.0.0"
        ;;
    *)
        # Explicit version string passed like 1.2.3
        NEW_VERSION="$BUMP_TYPE"
        ;;
esac

echo "=================================================="
echo "🚀 MacAlarm Now Release"
echo "Current Version: $CURRENT_VERSION"
echo "Target  Version: $NEW_VERSION"
echo "=================================================="

# 3. Save incremented version
echo "$NEW_VERSION" > "$VERSION_FILE"
echo "✓ Saved new version '$NEW_VERSION' to $VERSION_FILE"

# 4. Build App Bundle
chmod +x scripts/bundle_app.sh
./scripts/bundle_app.sh "$NEW_VERSION"

# 5. Build Distribution DMG (MacAlarm-x.x.x.dmg)
chmod +x scripts/create_dmg.sh
./scripts/create_dmg.sh "$NEW_VERSION"

DMG_FILE="MacAlarm-${NEW_VERSION}.dmg"

# 6. Auto-update /Applications/MacAlarm Now.app if previously installed
if [ -d "/Applications/MacAlarm Now.app" ]; then
    echo "=== Updating /Applications/MacAlarm Now.app ==="
    pkill -f "MacAlarm" || true
    rm -rf "/Applications/MacAlarm Now.app"
    cp -R "MacAlarm Now.app" "/Applications/"
    echo "✓ Updated /Applications/MacAlarm Now.app to v$NEW_VERSION"
fi

# 7. Git commit & tag if git repository
if [ -d ".git" ]; then
    echo "=== Creating Git Commit & Tag for v$NEW_VERSION ==="
    git add -u 2>/dev/null || true
    git add "$VERSION_FILE" "README.md" 2>/dev/null || true
    if git diff --staged --quiet; then
        echo "No additional git changes to stage."
    else
        git commit -m "chore(release): bump version to $NEW_VERSION" || true
    fi
    git tag -a "v$NEW_VERSION" -m "Release v$NEW_VERSION" 2>/dev/null || true
    echo "✓ Tagged v$NEW_VERSION in git"
fi

echo ""
echo "=================================================="
echo "🎉 SUCCESS: Release v$NEW_VERSION Complete!"
echo "📦 Disk Image: $DMG_FILE"
ls -lh "$DMG_FILE"
echo "=================================================="
