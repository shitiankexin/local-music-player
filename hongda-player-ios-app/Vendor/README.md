This folder is populated by `scripts/build-flac.sh` on macOS.

No precompiled Apple binaries, Apple SDK code, or libFLAC third-party code are redistributed by default with the source tree (a local `libFLAC.xcframework` may exist after running the script).

The script fetches Xiph.org FLAC 1.5.0 and builds two static XCFramework slices for iOS arm64 and iOS Simulator arm64 (`IPHONEOS_DEPLOYMENT_TARGET=18.0`).

Before distributing **洪达快播**, comply with the libFLAC `COPYING.Xiph` (BSD-style) notice.
