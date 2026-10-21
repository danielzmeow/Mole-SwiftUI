#!/bin/bash
set -euo pipefail

MODE="${1:-run}"
case "$MODE" in
    run | --build-only | --debug | --logs | --telemetry | --verify) ;;
    *)
        echo "Usage: $0 [run|--build-only|--debug|--logs|--telemetry|--verify]" >&2
        exit 2
        ;;
esac

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/script/swift_environment.sh"
APP_NAME="MoleShell"
BUNDLE_ID="dev.moleswiftui.shell"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"

if [[ "$MODE" != "--build-only" ]]; then
    /usr/bin/pkill -x "$APP_NAME" > /dev/null 2>&1 || true
fi
swift build --package-path "$ROOT_DIR/macos"
BUILD_DIR="$(swift build --package-path "$ROOT_DIR/macos" --show-bin-path)"

rm -rf -- "$APP_BUNDLE" # SAFE: exact project-local generated app bundle, never a user-installed app.
mkdir -p "$APP_CONTENTS/MacOS" "$APP_CONTENTS/Resources"
cp "$BUILD_DIR/$APP_NAME" "$APP_CONTENTS/MacOS/$APP_NAME"
chmod +x "$APP_CONTENTS/MacOS/$APP_NAME"
python3 "$ROOT_DIR/script/stage_cli.py"

cat > "$APP_CONTENTS/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>Mole SwiftUI</string>
  <key>CFBundleDisplayName</key><string>Mole SwiftUI</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
/usr/bin/codesign --force --sign - "$APP_BUNDLE"

case "$MODE" in
    --build-only) echo "Built $APP_BUNDLE" ;;
    run) /usr/bin/open -n "$APP_BUNDLE" ;;
    --debug) lldb -- "$APP_CONTENTS/MacOS/$APP_NAME" ;;
    --logs | --telemetry)
        /usr/bin/open -n "$APP_BUNDLE"
        /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
        ;;
    --verify)
        /usr/bin/open -n "$APP_BUNDLE"
        sleep 2
        /usr/bin/pgrep -x "$APP_NAME" > /dev/null
        echo "$APP_NAME is running."
        ;;
esac
