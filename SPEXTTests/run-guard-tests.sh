#!/bin/sh
set -eu

# Compiles the services and the guard tests with plain swiftc (no Xcode needed) and runs them
# twice, once with a German and once with an English interface. The binary runs inside a tiny
# bundle that carries the real string catalog, so the localized texts are the ones the app ships.

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/SPEXTGuardTests.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

MODULE_CACHE="$WORK_DIR/ModuleCache"
BUNDLE="$WORK_DIR/SPEXTGuardTests.app"
TEST_BINARY="$BUNDLE/Contents/MacOS/SPEXTTranscriptionGuardTests"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"

python3 -I "$ROOT_DIR/SPEXTTests/xcstrings_tool.py" check \
  "$ROOT_DIR/SPEXT/Localizable.xcstrings" "$ROOT_DIR/SPEXT"
python3 -I "$ROOT_DIR/SPEXTTests/xcstrings_tool.py" lproj \
  "$ROOT_DIR/SPEXT/Localizable.xcstrings" "$BUNDLE/Contents/Resources"

cat > "$BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>de.Rehkopf.SPEXT.GuardTests</string>
    <key>CFBundleExecutable</key><string>SPEXTTranscriptionGuardTests</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleLocalizations</key><array><string>en</string><string>de</string></array>
</dict>
</plist>
PLIST

swiftc \
  -D SPEXT_RECORDER_TESTS \
  -module-cache-path "$MODULE_CACHE" \
  -o "$TEST_BINARY" \
  "$ROOT_DIR/SPEXT/Services/AppStatusText.swift" \
  "$ROOT_DIR/SPEXT/Services/FrenchQuoteNormalizer.swift" \
  "$ROOT_DIR/SPEXT/Services/TranscriptionQuality.swift" \
  "$ROOT_DIR/SPEXT/Services/HotkeySettings.swift" \
  "$ROOT_DIR/SPEXT/Services/PermissionChecklist.swift" \
  "$ROOT_DIR/SPEXT/Services/LifecyclePolicies.swift" \
  "$ROOT_DIR/SPEXT/Models/AudioDevice.swift" \
  "$ROOT_DIR/SPEXT/Services/TranscriptionService.swift" \
  "$ROOT_DIR/SPEXT/Services/PolishService.swift" \
  "$ROOT_DIR/SPEXT/Services/RecordingAssembler.swift" \
  "$ROOT_DIR/SPEXT/Services/AudioRecorder.swift" \
  "$ROOT_DIR/SPEXT/Services/HotkeyManager.swift" \
  "$ROOT_DIR/SPEXTTests/TranscriptionGuardTests.swift"

for LANGUAGE in de en; do
  echo "── Interface language: $LANGUAGE"
  "$TEST_BINARY" -AppleLanguages "($LANGUAGE)" -AppleLocale "$LANGUAGE"
done
