#!/bin/sh
set -eu

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MODULE_CACHE="${TMPDIR:-/tmp}/SPEXTModuleCache"
TEST_BINARY="${TMPDIR:-/tmp}/SPEXTTranscriptionGuardTests"

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
  "$ROOT_DIR/SPEXTTests/TranscriptionGuardTests.swift"

"$TEST_BINARY"
