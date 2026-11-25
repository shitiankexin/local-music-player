# hongdakuaibo portable tests

Run `bash TestsPortable/run-linux.sh` from any location with a working Swift toolchain (Linux or macOS without iOS SDK).

These verify **real file system behavior** for directory hierarchy preservation, content-equivalent duplication decisions, renamed sidecars, unique LRC matching, deletion, and metadata cache invalidation. Tests replace Apple-only `CryptoKit`, `NSFileCoordinator`, and the libFLAC decoder with **test doubles**. The digest double is intentionally a fast deterministic FNV-like hash, *not cryptographic SHA-256*. Use iOS XCTest in Xcode to validate the real CryptoKit and Apple file-provider implementations.

Test doubles are not included in the iOS build because XcodeGen only includes `hongdakuaibo/` and `Tests/`.
