#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PROJECT="${PROJECT:-$REPO_ROOT/WiFiPulse.xcodeproj}"
SCHEME="${SCHEME:-MacSpeedMonitor}"
CONFIGURATION="${CONFIGURATION:-Release}"
DIST_DIR="${DIST_DIR:-$REPO_ROOT/dist}"
APP_NAME="${APP_NAME:-MacSpeedMonitor}"
VOLUME_NAME="${VOLUME_NAME:-MacSpeedMonitor}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

for command in xcodebuild ditto codesign hdiutil shasum xattr; do
    command -v "$command" >/dev/null 2>&1 || {
        echo "error: required command not found: $command" >&2
        exit 1
    }
done

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/MacSpeedMonitor-dist.XXXXXX")"
ARCHIVE_PATH="$WORK_DIR/$APP_NAME.xcarchive"
DMG_STAGE="$WORK_DIR/dmg"

cleanup() {
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

echo "Archiving $SCHEME ($CONFIGURATION)..."
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "generic/platform=macOS" \
    -archivePath "$ARCHIVE_PATH" \
    CODE_SIGNING_ALLOWED=NO \
    ONLY_ACTIVE_ARCH=NO \
    clean archive

ARCHIVED_APP="$ARCHIVE_PATH/Products/Applications/$APP_NAME.app"
if [[ ! -d "$ARCHIVED_APP" ]]; then
    echo "error: archived app not found at $ARCHIVED_APP" >&2
    exit 1
fi

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"
SIGNED_APP="$WORK_DIR/$APP_NAME.app"
ditto --noextattr "$ARCHIVED_APP" "$SIGNED_APP"
xattr -cr "$SIGNED_APP"

sign_target() {
    local target="$1"
    shift
    local args=(--force --sign "$SIGN_IDENTITY")
    if [[ "$SIGN_IDENTITY" != "-" ]]; then
        args+=(--options runtime --timestamp)
    fi
    codesign "${args[@]}" "$@" "$target"
}

if [[ -d "$SIGNED_APP/Contents/Frameworks" ]]; then
    while IFS= read -r -d '' framework; do
        sign_target "$framework"
    done < <(find "$SIGNED_APP/Contents/Frameworks" -type d -name '*.framework' -prune -print0)

    while IFS= read -r -d '' library; do
        sign_target "$library"
    done < <(find "$SIGNED_APP/Contents/Frameworks" -type f -name '*.dylib' -print0)
fi

WIDGET_EXTENSION="$SIGNED_APP/Contents/PlugIns/WiFiPulseWidgetExtension.appex"
if [[ -d "$WIDGET_EXTENSION" ]]; then
    sign_target \
        "$WIDGET_EXTENSION" \
        --entitlements "$REPO_ROOT/WiFiPulseWidget/WiFiPulseWidget.entitlements"
fi

sign_target \
    "$SIGNED_APP" \
    --entitlements "$REPO_ROOT/Sources/MacSpeedMonitorApp/MacSpeedMonitor.entitlements"

codesign --verify --deep --strict --verbose=2 "$SIGNED_APP"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$SIGNED_APP/Contents/Info.plist")"
DMG_NAME="${DMG_NAME:-$APP_NAME-$VERSION.dmg}"
DMG_PATH="$DIST_DIR/$DMG_NAME"

mkdir -p "$DMG_STAGE"
ditto --noextattr "$SIGNED_APP" "$DMG_STAGE/$APP_NAME.app"
xattr -cr "$DMG_STAGE/$APP_NAME.app"
ln -s /Applications "$DMG_STAGE/Applications"

echo "Creating $DMG_NAME..."
hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$DMG_STAGE" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

if [[ -n "$NOTARY_PROFILE" ]]; then
    if [[ "$SIGN_IDENTITY" == "-" ]]; then
        echo "error: NOTARY_PROFILE requires a Developer ID SIGN_IDENTITY" >&2
        exit 1
    fi
    echo "Submitting DMG for notarization..."
    xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG_PATH"
    xcrun stapler validate "$DMG_PATH"
fi

DIST_APP="$DIST_DIR/$APP_NAME.app"
ditto --noextattr "$SIGNED_APP" "$DIST_APP"
xattr -cr "$DIST_APP"
codesign --verify --deep --strict --verbose=2 "$DIST_APP"

(
    cd "$DIST_DIR"
    shasum -a 256 "$DMG_NAME" > SHA256SUMS.txt
)

echo
echo "Distribution artifacts created:"
echo "  App: $DIST_APP"
echo "  DMG: $DMG_PATH"
echo "  SHA: $DIST_DIR/SHA256SUMS.txt"
if [[ "$SIGN_IDENTITY" == "-" ]]; then
    echo "  Signing: ad hoc (users may need Privacy & Security > Open Anyway)"
else
    echo "  Signing: $SIGN_IDENTITY"
fi
