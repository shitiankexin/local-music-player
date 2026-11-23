# CHANGELOG

## 2.0.0 — Enhanced Local File Manager

### Added
- Directory picker for recursive `.flac`/`.lrc` import, preserving nested directory hierarchy.
- Streaming file copies through temporary staging files with progress and cancellation.
- SHA-256 content deduplication at import time; duplicate review groups for the existing catalog.
- Incremental catalog scan using path, byte length, and modified timestamp.
- Unique-title/filename LRC sidecar batch matching with ambiguity protection; root fallback also rejects ambiguous song names.
- Song deletion with a confirmation dialog, playlist reconciliation, and same-folder sidecar cleanup.
- Storage statistics for FLAC, LRC, extracted cover art, free disk space, matched song count.
- A fifth tab: Library Manager.
- App privacy manifest for the required-reason file timestamp / disk space API usage.
- Portable file management integration tests and iOS XCTest cases.

### Changed
- `MusicTrack` gains `modifiedAt` and optional cached `sha256`, with V1 JSON compatibility.
- Catalog scanning, copying, hashing, and deleting run outside the main actor.
- `PlayerStore` can safely release a currently playing song before deleting its file.
- Finder/AirDrop imports trigger non-overlapping scans; concurrent imported URLs are queued.
- App version is set to 2.0.0.

### Known limitations
- Requires actual macOS Xcode build and iPhone smoke testing before production use.
- Same music/audio but different FLAC tag bytes is intentionally NOT considered an exact duplicate.
- LRC is matched by unique filename or unique title, not arbitrary fuzzy matching.
- Rename/move outside the app can change track UUID and invalidate playlist references.
- Cancel is not transactional; successfully completed copies remain.
