#!/usr/bin/env bash
set -euo pipefail

# Run this on macOS with Xcode, git, CMake and Ninja installed.
# Builds the Xiph.org FLAC 1.5.0 STATIC decoder for iOS devices and Apple Silicon Simulator.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLAC_VERSION="1.5.0"
SRC="$ROOT/.build/xiph-flac"
BUILD="$ROOT/.build"
mkdir -p "$BUILD" "$ROOT/Vendor/Headers"

for cmd in xcodebuild xcrun cmake ninja git; do
  command -v "$cmd" >/dev/null || { echo "Missing required command: $cmd"; exit 1; }
done
if [ ! -f "$SRC/CMakeLists.txt" ]; then
  git clone --depth 1 --branch "$FLAC_VERSION" https://github.com/xiph/flac.git "$SRC"
fi

build_one() {
  local platform="$1"
  local sysroot="$2"
  local prefix="$BUILD/$platform"
  cmake -S "$SRC" -B "$prefix" -G Ninja \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_SYSROOT="$sysroot" \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 \
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
cp -R "$SRC/include/FLAC" "$ROOT/Vendor/Headers/"
rm -rf "$ROOT/Vendor/libFLAC.xcframework"
xcodebuild -create-xcframework \
  -library "$(cat "$BUILD/iphoneos-library.txt")" -headers "$ROOT/Vendor/Headers" \
  -library "$(cat "$BUILD/iphonesimulator-library.txt")" -headers "$ROOT/Vendor/Headers" \
  -output "$ROOT/Vendor/libFLAC.xcframework"
echo "Built: $ROOT/Vendor/libFLAC.xcframework"
