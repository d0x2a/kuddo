#!/usr/bin/env bash
# Builds a signed + notarized + stapled Kuddo.app and Kuddo-<version>.dmg
# under ./build/. The binary is Apple silicon only (arm64).
#
# Optional env vars
# -----------------
#   BUNDLE_ID    Defaults to com.d0x2a.kuddo.
#   VERSION      Defaults to current version. Goes into
#                CFBundleShortVersionString.
#   BUILD_NUMBER Defaults to one derived from VERSION. Goes into
#                CFBundleVersion.
#
# Kuddo 1.0.0 kept mTerm's bundle id, com.d0x2a.mTerm, so the notification
# permission and Files & Folders grants carried over. Sharing an id let macOS
# mix the two apps up, so from 1.0.1 Kuddo has its own and asks for those
# permissions again.

set -euo pipefail

DEVELOPER_ID_APPLICATION="${DEVELOPER_ID_APPLICATION:-Developer ID Application: Dox2A Labs LLC (7JD669BMB4)}"
NOTARY_PROFILE="${NOTARY_PROFILE:-kuddo-notary}"
BUNDLE_ID="${BUNDLE_ID:-com.d0x2a.kuddo}"
VERSION="${VERSION:-1.0.6}"

# CFBundleVersion is what macOS ranks copies of an app by, so it has to rise
# with every release. One integer per version — major·10000 + minor·100 +
# patch — does that: 1.0.1 is 10001.
IFS=. read -r V_MAJOR V_MINOR V_PATCH <<< "$VERSION"
V_PATCH="${V_PATCH:-0}"
(( V_MINOR < 100 && V_PATCH < 100 )) || {
    echo "✗ $VERSION doesn't fit the build-number scheme" >&2
    exit 1
}
BUILD_NUMBER="${BUILD_NUMBER:-$(( V_MAJOR * 10000 + V_MINOR * 100 + V_PATCH ))}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
APP="$BUILD/Kuddo.app"
ICONSET="$BUILD/AppIcon.iconset"
DMG="$BUILD/Kuddo-$VERSION.dmg"
ZIP="$BUILD/Kuddo.zip"

echo "▶ cleaning $BUILD"
rm -rf "$BUILD"
mkdir -p "$BUILD" "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "▶ building release binary (arm64)"
# Apple silicon only, from Kuddo 1.0.0 on: mTerm 1.6.0 is the last release
# with an Intel slice, and the cask declares `depends_on arch: :arm64` so
# Homebrew won't hand this build to an Intel Mac. The arch is spelled out
# rather than left to the host, so the result doesn't depend on which Mac
# runs the script, and the arch flags have to be on --show-bin-path too or
# it answers with a different build's directory. The lipo check below is what
# catches a wrong slice, so keep it.
BUILD_FLAGS=(-c release --arch arm64)
swift build "${BUILD_FLAGS[@]}"
BIN_DIR="$(swift build "${BUILD_FLAGS[@]}" --show-bin-path)"
cp "$BIN_DIR/Kuddo" "$APP/Contents/MacOS/Kuddo"

ARCHS="$(lipo -archs "$APP/Contents/MacOS/Kuddo")"
[[ "$ARCHS" == "arm64" ]] || {
    echo "✗ expected an arm64 binary, got: $ARCHS" >&2
    exit 1
}
echo "  binary: $ARCHS"

echo "▶ writing Info.plist (bundle=$BUNDLE_ID, version=$VERSION, build=$BUILD_NUMBER)"
sed -e "s|__BUNDLE_ID__|$BUNDLE_ID|g" \
    -e "s|__VERSION__|$VERSION|g" \
    -e "s|__BUILD_NUMBER__|$BUILD_NUMBER|g" \
    "$ROOT/Resources/Info.plist" > "$APP/Contents/Info.plist"

echo "▶ baking AppIcon.icns"
"$APP/Contents/MacOS/Kuddo" --export-iconset "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

echo "▶ codesigning .app"
codesign --force --options runtime \
    --entitlements "$ROOT/Resources/Entitlements.plist" \
    --sign "$DEVELOPER_ID_APPLICATION" \
    --timestamp \
    "$APP"
codesign --verify --strict --verbose=2 "$APP"

echo "▶ submitting .app for notarization (this can take a few minutes)"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait
xcrun stapler staple "$APP"
rm -f "$ZIP"

echo "▶ creating DMG"
# Render the HiDPI background image (Kuddo itself exports the PNGs;
# tiffutil packs @1x + @2x into a single .tiff so Finder picks the right
# rep on Retina displays).
BG_DIR="$BUILD/dmg-bg"
"$APP/Contents/MacOS/Kuddo" --export-dmg-background "$BG_DIR"
tiffutil -cathidpicheck "$BG_DIR/background.png" "$BG_DIR/background@2x.png" \
    -out "$BG_DIR/background.tiff" >/dev/null

# create-dmg (from Homebrew) handles layout: positions Kuddo.app on the
# left, an Applications drop-link on the right, paints the background, and
# sets the volume icon so the mounted disk shows the app icon rather than
# the generic removable-drive one.
# It returns non-zero if a Finder AppleScript step transiently fails, so
# we ignore exit status as long as the DMG actually got written.
create-dmg \
    --volname "Kuddo $VERSION" \
    --volicon "$APP/Contents/Resources/AppIcon.icns" \
    --background "$BG_DIR/background.tiff" \
    --window-pos 200 120 \
    --window-size 600 400 \
    --icon-size 128 \
    --icon "Kuddo.app" 150 200 \
    --app-drop-link 450 200 \
    --no-internet-enable \
    "$DMG" \
    "$APP" || true
test -f "$DMG"

echo "▶ codesigning DMG"
codesign --force \
    --sign "$DEVELOPER_ID_APPLICATION" \
    --timestamp \
    "$DMG"

echo "▶ submitting DMG for notarization"
xcrun notarytool submit "$DMG" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait
xcrun stapler staple "$DMG"

echo "▶ verifying Gatekeeper acceptance"
spctl --assess --type execute --verbose "$APP"
spctl --assess --type open --context context:primary-signature --verbose "$DMG"

echo
echo "✓ built: $DMG"
