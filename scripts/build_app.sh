#!/bin/bash
#
# Build TeXtUtility.app from the Autotyper Swift package and install it to
# ~/Applications. Run this any time you want the system app to reflect
# in-tree changes.
#
# Usage:
#   ./scripts/build_app.sh                   # release build
#   ./scripts/build_app.sh --debug           # debug build
#   ./scripts/build_app.sh --launch          # release build + open the app
#
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"

CONFIG="release"
LAUNCH="0"
for arg in "$@"; do
    case "$arg" in
        --debug)  CONFIG="debug" ;;
        --launch) LAUNCH="1" ;;
        *) echo "unknown arg: $arg" >&2; exit 2 ;;
    esac
done

APP_NAME="TeXtUtility"
BUNDLE_ID="com.local.textutility"
APP_DST="$HOME/Applications/${APP_NAME}.app"

ICON_SRC="${ICON_SRC:-$HOME/Downloads/keypress.png}"
BUILD_TMP="$ROOT/.build/app-build"

echo "[1/5] icon"
if [ ! -f "$ICON_SRC" ]; then
    echo "icon source not found: $ICON_SRC" >&2
    echo "set ICON_SRC=/path/to/png or place a file at that location" >&2
    exit 1
fi
rm -rf "$BUILD_TMP/AppIcon.iconset" "$BUILD_TMP/AppIcon.icns"
mkdir -p "$BUILD_TMP"
# Also write the cropped logo into Sources/Autotyper/Resources so the next
# `swift build` picks it up via SPM and the in-app UI can load it via
# Bundle.module.
swift "$ROOT/scripts/build_icon.swift" \
    "$ICON_SRC" \
    "$BUILD_TMP/AppIcon.iconset" \
    "$ROOT/Sources/Autotyper/Resources/AppLogo.png"
iconutil -c icns "$BUILD_TMP/AppIcon.iconset" -o "$BUILD_TMP/AppIcon.icns"

echo "[2/5] swift build ($CONFIG)"
swift build -c "$CONFIG"

BIN_PATH="$ROOT/.build/$CONFIG/Autotyper"
RES_BUNDLE="$ROOT/.build/$CONFIG/Autotyper_Autotyper.bundle"
if [ ! -x "$BIN_PATH" ]; then
    echo "build did not produce $BIN_PATH" >&2; exit 1
fi
if [ ! -d "$RES_BUNDLE" ]; then
    echo "expected resource bundle missing: $RES_BUNDLE" >&2; exit 1
fi

echo "[3/5] assemble app bundle"
# Quit any running instance so the binary swap succeeds and the user gets
# the freshly-built code on next launch.
pkill -x "$APP_NAME" 2>/dev/null || true
rm -rf "$APP_DST"
mkdir -p "$APP_DST/Contents/MacOS"
mkdir -p "$APP_DST/Contents/Resources"

cp "$BIN_PATH" "$APP_DST/Contents/MacOS/${APP_NAME}"
chmod +x "$APP_DST/Contents/MacOS/${APP_NAME}"

# SPM resource bundle. Bundle.module resolves it via Bundle.main.resourceURL,
# which is Contents/Resources/ in a packaged .app. (Don't put a duplicate in
# MacOS/ — codesign --deep then fails to sign the non-code bundle in there.)
cp -R "$RES_BUNDLE" "$APP_DST/Contents/Resources/"

cp "$BUILD_TMP/AppIcon.icns" "$APP_DST/Contents/Resources/AppIcon.icns"

cat > "$APP_DST/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleExecutable</key><string>${APP_NAME}</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSAccessibilityUsageDescription</key><string>${APP_NAME} synthesizes keystrokes to your chosen target window.</string>
</dict>
</plist>
EOF

echo "[4/5] sign"
# Prefer a stable self-signed cert if the user has run setup_dev_cert.sh.
# The "designated requirement" stays the same across rebuilds, so the
# Accessibility grant survives. Fall back to ad-hoc signing if no cert is
# installed (TCC will reset on every rebuild in that case).
SIGN_IDENTITY="TeXtUtility Local Dev"
# `find-identity` without `-v` lists certs even when not in the trust store —
# self-signed certs are usable by codesign regardless of trust state.
MATCH_COUNT=$(security find-identity -p codesigning 2>/dev/null | grep -c "\"$SIGN_IDENTITY\"" || true)
if [ "$MATCH_COUNT" -gt 1 ]; then
    echo "  ERROR: $MATCH_COUNT certs named '$SIGN_IDENTITY' in your keychain — codesign would be ambiguous." >&2
    echo "  list them: security find-identity -p codesigning | grep '$SIGN_IDENTITY'" >&2
    echo "  delete extras: security delete-identity -Z <SHA1> ~/Library/Keychains/login.keychain-db" >&2
    exit 1
fi
if [ "$MATCH_COUNT" -eq 1 ]; then
    echo "  using stable identity: $SIGN_IDENTITY"
    codesign --force --sign "$SIGN_IDENTITY" "$APP_DST/Contents/MacOS/${APP_NAME}"
    codesign --force --sign "$SIGN_IDENTITY" "$APP_DST"
else
    echo "  ad-hoc (TCC grant will reset on rebuild — run scripts/setup_dev_cert.sh once for a stable grant)"
    codesign --force --sign - "$APP_DST/Contents/MacOS/${APP_NAME}"
    codesign --force --sign - "$APP_DST"
fi

echo "[5/5] cache reset"
# Touch so Finder/LaunchServices notice the change.
touch "$APP_DST"
# Force LaunchServices to re-register the bundle (otherwise stale Info.plist
# can survive a rebuild and Spotlight may not see the new icon/name).
/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister \
    -f "$APP_DST" >/dev/null 2>&1 || true

echo
echo "installed: $APP_DST"

if [ "$LAUNCH" = "1" ]; then
    # Kill any prior instance so the new binary takes over.
    pkill -x "$APP_NAME" 2>/dev/null || true
    sleep 0.3
    open "$APP_DST"
fi
