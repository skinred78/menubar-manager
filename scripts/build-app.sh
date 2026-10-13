#!/bin/bash
# Builds MenuBar Manager.app, signs it, and optionally installs it.
#
#   ./scripts/build-app.sh            build into ./build
#   ./scripts/build-app.sh --install  also copy to /Applications and launch
#
# Signing uses $SIGN_IDENTITY if set, otherwise the first "Apple Development"
# or "Developer ID Application" identity in your keychain, otherwise ad hoc.
set -euo pipefail

cd "$(dirname "$0")/.."
APP_NAME="MenuBar Manager"
APP="build/$APP_NAME.app"

swift build -c release --arch arm64

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --arch arm64 --show-bin-path)/MenuBarManager" "$APP/Contents/MacOS/MenuBarManager"
cp Resources/Info.plist "$APP/Contents/Info.plist"

if [[ -z "${SIGN_IDENTITY:-}" ]]; then
    SIGN_IDENTITY=$(security find-identity -v -p codesigning \
        | grep -E '"(Developer ID Application|Apple Development):' \
        | head -n1 | sed -E 's/.*"(.*)"/\1/' || true)
fi
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
echo "Signing with: $SIGN_IDENTITY"
codesign --force --options runtime --timestamp=none --sign "$SIGN_IDENTITY" "$APP"
codesign --verify --verbose "$APP"

echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x MenuBarManager || true
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$APP" /Applications/
    open "/Applications/$APP_NAME.app"
    echo "Installed and launched /Applications/$APP_NAME.app"
fi
