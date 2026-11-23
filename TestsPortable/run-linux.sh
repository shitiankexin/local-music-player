#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
swiftc -version
# CryptoKit and NSFileCoordinator are iOS/macOS APIs. Linux test doubles implement
# the same interface solely for file behavior tests (digest stub is NOT SHA-256).
sed '/^import CryptoKit$/d' "$ROOT/FLACPlayer/Services/LibraryImportWorker.swift" > "$TMP/LibraryImportWorkerPortable.swift"
COMMON=(
  "$ROOT/FLACPlayer/Models/MusicTrack.swift"
  "$ROOT/FLACPlayer/Models/LibraryManagementModels.swift"
  "$ROOT/FLACPlayer/Services/LibraryFileRules.swift"
)
swiftc "$ROOT/TestsPortable/MockAppleAPIs.swift" "${COMMON[@]}" \
  "$TMP/LibraryImportWorkerPortable.swift" \
  "$ROOT/FLACPlayer/Services/LibraryMaintenanceWorker.swift" \
  "$ROOT/TestsPortable/ImportIntegration.swift" -o "$TMP/import-test"
"$TMP/import-test"
swiftc "${COMMON[@]}" \
  "$ROOT/TestsPortable/MockFLACDecoder.swift" \
  "$ROOT/FLACPlayer/Services/LibraryIndexer.swift" \
  "$ROOT/TestsPortable/IndexIntegration.swift" -o "$TMP/index-test"
"$TMP/index-test"
printf '%s\n' 'All portable tests passed. The real SHA-256, libFLAC, AVAudioEngine, SwiftUI and Xcode build require Apple testing.'
