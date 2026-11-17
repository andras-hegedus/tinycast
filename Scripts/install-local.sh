#!/bin/bash
# Build this checkout as the stable-channel Tinycast.app and install it over /Applications. Run from prod.
set -euo pipefail
cd "$(dirname "$0")/.." || exit 1

APP_NAME=Tinycast
BUNDLE_ID=com.abueammar.tinycast
DEST="/Applications/$APP_NAME.app"
BACKUPS="$HOME/Library/Application Support/Tinycast Fork Backups"
DERIVED=build/install

branch="$(git rev-parse --abbrev-ref HEAD)"
if [ "$branch" != prod ] && [ "${ALLOW_ANY_BRANCH:-0}" != 1 ]; then
    echo "On '$branch', not prod. Switch to prod, or set ALLOW_ANY_BRANCH=1." >&2
    exit 1
fi
if [ -n "$(git status --porcelain)" ] && [ "${ALLOW_DIRTY:-0}" != 1 ]; then
    echo "Uncommitted changes; commit them or set ALLOW_DIRTY=1." >&2
    exit 1
fi

# A stable identity keeps macOS's permission grants across rebuilds; ad-hoc signing would not.
IDENTITY="${TINYCAST_SIGNING_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
    IDENTITY="$(security find-identity -v -p codesigning |
        sed -n 's/.*"\(Apple Development: [^"]*\)".*/\1/p' | head -1)"
fi
if [ -z "$IDENTITY" ]; then
    IDENTITY="Tinycast Self-Signed"
fi
TEAM="$(security find-certificate -c "$IDENTITY" -p 2>/dev/null |
    openssl x509 -noout -subject 2>/dev/null | sed -n 's/.*OU=\([A-Z0-9]*\).*/\1/p')"
echo "Signing with: $IDENTITY${TEAM:+ (team $TEAM)}"

# The release this prod sits on; the build number only has to grow.
VERSION="$(git describe --tags --abbrev=0 --match 'v[0-9]*.[0-9]*.[0-9]*' --exclude '*-*' | sed 's/^v//')"
BUILD_NUMBER="$(git rev-list --count HEAD)"
echo "Building $APP_NAME $VERSION ($BUILD_NUMBER, $(git rev-parse --short HEAD))"

xcodegen generate --quiet
xcodebuild -project Tinycast.xcodeproj -scheme Tinycast -configuration Release \
    -derivedDataPath "$DERIVED" -quiet \
    ARCHS="$(uname -m)" ONLY_ACTIVE_ARCH=NO \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$IDENTITY" DEVELOPMENT_TEAM="$TEAM" \
    PRODUCT_NAME="$APP_NAME" TINYCAST_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
    MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    build

BUILT="$DERIVED/Build/Products/Release/$APP_NAME.app"
codesign --verify --deep --strict "$BUILT"
echo "Built and verified: $BUILT"

if pgrep -xq "$APP_NAME"; then
    echo "Quitting the running ${APP_NAME}…"
    osascript -e "tell application id \"$BUNDLE_ID\" to quit" || true
    for _ in $(seq 1 30); do pgrep -xq "$APP_NAME" || break; sleep 1; done
    if pgrep -xq "$APP_NAME"; then
        echo "$APP_NAME did not quit; quit it and run this again." >&2
        exit 1
    fi
fi

# Kept outside /Applications: two bundles with one id would split URL-scheme and login-item routing.
if [ -d "$DEST" ]; then
    mkdir -p "$BACKUPS"
    old_version="$(defaults read "$DEST/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo unknown)"
    old_team="$(codesign -dv "$DEST" 2>&1 | sed -n 's/^TeamIdentifier=//p')"
    # Someone else's build is the way back to upstream, so it is never rotated out.
    kind=fork
    [ -n "$TEAM" ] && [ "$old_team" != "$TEAM" ] && kind=upstream
    backup="$BACKUPS/$APP_NAME-$kind-$(date +%Y%m%d-%H%M%S)-$old_version.zip"
    ditto -c -k --keepParent --sequesterRsrc "$DEST" "$backup"
    echo "Backed up the installed app to: $backup"
    # Names sort by timestamp, so all but the newest three fork backups go.
    fork_backups=()
    for zip in "$BACKUPS/$APP_NAME-fork-"*.zip; do [ -e "$zip" ] && fork_backups+=("$zip"); done
    count=${#fork_backups[@]}
    for ((i = 0; i < count - 3; i++)); do rm -f "${fork_backups[$i]}"; done
    rm -rf "$DEST"
fi

ditto "$BUILT" "$DEST"
echo "Installed $DEST"
open "$DEST"
