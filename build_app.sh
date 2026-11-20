#!/bin/bash
# Build StudyTimer.app on macOS (used by GitHub Actions and for local builds).
set -e
cd "$(dirname "$0")"

APP="StudyTimer.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
printf "APPL????" > "$APP/Contents/PkgInfo"

# Icon: committed as base64 text so it can live in git as a text file
if [ -f AppIcon.icns.b64 ]; then
  base64 --decode -i AppIcon.icns.b64 -o "$APP/Contents/Resources/AppIcon.icns" 2>/dev/null \
    || openssl base64 -d -in AppIcon.icns.b64 -out "$APP/Contents/Resources/AppIcon.icns"
fi

swiftc -O \
  -sdk "$(xcrun --show-sdk-path)" \
  -framework Cocoa \
  -o "$APP/Contents/MacOS/StudyTimer" \
  main.swift

chmod +x "$APP/Contents/MacOS/StudyTimer"
codesign --force --deep --sign - "$APP" || true
echo "Built $APP"
