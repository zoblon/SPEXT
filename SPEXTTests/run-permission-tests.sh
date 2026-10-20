#!/bin/sh
set -eu
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/SPEXTPermissionTests.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
swiftc -module-cache-path "$WORK_DIR/ModuleCache" \
  "$ROOT_DIR/SPEXT/Services/PermissionRecoveryPolicy.swift" \
  "$ROOT_DIR/SPEXT/Services/PermissionRecoveryIdentity.swift" \
  "$ROOT_DIR/SPEXTTests/PermissionRecoveryTests.swift" \
  -o "$WORK_DIR/PermissionRecoveryTests"
"$WORK_DIR/PermissionRecoveryTests"
