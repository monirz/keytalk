#!/bin/bash
# Builds Keytalk.app (menu bar, ad-hoc signed) into ./build.
set -euo pipefail
cd "$(dirname "$0")"

APP=build/Keytalk.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

swiftc -O -target arm64-apple-macos12 \
  -framework Cocoa -framework AVFoundation -framework Speech -framework Carbon \
  Sources/*.swift -o "$APP/Contents/MacOS/Keytalk"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>Keytalk</string>
  <key>CFBundleIdentifier</key><string>com.monirz.keytalk</string>
  <key>CFBundleName</key><string>Keytalk</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
  <key>LSUIElement</key><true/>
  <key>NSMicrophoneUsageDescription</key><string>Keytalk records your voice while you hold the dictation key.</string>
  <key>NSSpeechRecognitionUsageDescription</key><string>Keytalk turns your speech into text.</string>
</dict>
</plist>
PLIST

# Sign with a stable identity when there is one. macOS ties the Accessibility
# permission to the signature: with ad-hoc signing ("-") every rebuild looks
# like a new app and silently loses the permission. Override the identity
# with KEYTALK_SIGN_IDENTITY, for example a Developer ID for releases.
IDENTITY="${KEYTALK_SIGN_IDENTITY:-Keytalk Local Signing}"
if security find-identity -p codesigning | grep -qF "\"$IDENTITY\""; then
  codesign --force --sign "$IDENTITY" "$APP"
else
  echo "warning: no '$IDENTITY' signing identity, signing ad-hoc." >&2
  echo "         Accessibility permission will need re-granting after each rebuild." >&2
  codesign --force --sign - "$APP"
fi
echo "Built $APP"
