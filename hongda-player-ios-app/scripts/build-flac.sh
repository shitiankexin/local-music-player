#!/usr/bin/env bash
set -euo pipefail

# Run this on macOS with Xcode, CMake and Ninja installed.
# Builds the Xiph.org FLAC 1.5.0 STATIC decoder for iOS devices and Apple Silicon Simulator.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLAC_VERSION="1.5.0"
SRC="$ROOT/.build/xiph-flac"
BUILD="$ROOT/.build"
TARBALL="$BUILD/flac-${FLAC_VERSION}.tar.gz"
mkdir -p "$BUILD" "$ROOT/Vendor/Headers"

# Prefer full Xcode when xcode-select still points at Command Line Tools.
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

for cmd in xcodebuild xcrun cmake ninja; do
  if ! command -v "$cmd" >/dev/null; then
    echo "Missing required command: $cmd"
    echo "Install with: brew install cmake ninja"
    echo "And ensure Xcode is selected: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
    exit 1
  fi
done

fetch_source() {
  if [[ -f "$SRC/CMakeLists.txt" ]]; then
    return 0
  fi
  /bin/rm -rf "$SRC"
  mkdir -p "$BUILD"

  if [[ ! -f "$TARBALL" ]]; then
    echo "→ Downloading FLAC ${FLAC_VERSION} source"
    curl -L --http1.1 --retry 3 --retry-delay 2 \
      -o "$TARBALL" \
      "https://github.com/xiph/flac/archive/refs/tags/${FLAC_VERSION}.tar.gz"
  fi

  echo "→ Extracting $TARBALL"
  tar -xzf "$TARBALL" -C "$BUILD"
  mv "$BUILD/flac-${FLAC_VERSION}" "$SRC"
}

fetch_source

build_one() {
  local platform="$1"
  local sysroot="$2"
  local prefix="$BUILD/$platform"
  cmake -S "$SRC" -B "$prefix" -G Ninja \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_SYSROOT="$sysroot" \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=18.0 \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DBUILD_SHARED_LIBS=OFF \
    -DINSTALL_MANPAGES=OFF \
    -DBUILD_CXXLIBS=OFF \
    -DBUILD_PROGRAMS=OFF \
    -DBUILD_EXAMPLES=OFF \
    -DBUILD_TESTING=OFF \
    -DBUILD_DOCS=OFF \
    -DWITH_OGG=OFF
  cmake --build "$prefix" --parallel 4
  local lib
  lib="$(find "$prefix" -name libFLAC.a -type f -print -quit)"
  test -f "$lib" || { echo "libFLAC.a not found in $prefix"; exit 1; }
  echo "$lib" > "$BUILD/$platform-library.txt"
}

build_one iphoneos iphoneos
build_one iphonesimulator iphonesimulator

# Upstream FLAC 1.5.0 docs name the param "allow" while the API uses "value"
# (Xcode: "Parameter 'allow' not found in the function declaration").
perl -pi -e 's/\\param  allow            Whether to allow chained streams\./\\param  value            Whether to allow chained streams./' \
  "$SRC/include/FLAC/stream_decoder.h"

/bin/rm -rf "$ROOT/Vendor/Headers/FLAC"
cp -R "$SRC/include/FLAC" "$ROOT/Vendor/Headers/"
rm -rf "$ROOT/Vendor/libFLAC.xcframework"
xcodebuild -create-xcframework \
  -library "$(cat "$BUILD/iphoneos-library.txt")" -headers "$ROOT/Vendor/Headers" \
  -library "$(cat "$BUILD/iphonesimulator-library.txt")" -headers "$ROOT/Vendor/Headers" \
  -output "$ROOT/Vendor/libFLAC.xcframework"
echo "Built: $ROOT/Vendor/libFLAC.xcframework"
