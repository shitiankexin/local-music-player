import Foundation

struct LibraryProgress: Sendable {
    var title: String
    var detail: String = ""
    var completed: Int64 = 0
    var total: Int64 = 0

    var fraction: Double? {
        total > 0 ? min(1, max(0, Double(completed) / Double(total))) : nil
    }
}

struct LibraryStorage: Sendable {
    var audioBytes: Int64 = 0
    var lyricBytes: Int64 = 0
    var artworkBytes: Int64 = 0
    var freeBytes: Int64 = 0
    var lyricFiles: Int = 0
    var matchedTracks: Int = 0

    var totalBytes: Int64 { audioBytes + lyricBytes + artworkBytes }
}

struct ScanReport: Sendable {
    var added = 0
    var updated = 0
    var reused = 0
    var removed = 0
    var failed = 0
    var messages: [String] = []

    var display: String {
        "新增 \(added) · 更新 \(updated) · 复用 \(reused) · 移除 \(removed) · 失败 \(failed)"
    }
}

struct ImportReport: Sendable {
    var importedAudio = 0
    var importedLyrics = 0
    var skippedDuplicates = 0
    var alreadyInLibrary = 0
    var conflicts = 0
    var failed = 0
    var cancelled = false
    var errors: [String] = []

    var display: String {
        "歌曲 \(importedAudio) · 歌词 \(importedLyrics) · 跳过重复 \(skippedDuplicates) · 命名冲突 \(conflicts) · 失败 \(failed)" + (cancelled ? " · 已取消" : "")
    }
}

struct LyricsMatchReport: Sendable {
    var matched = 0
    var alreadyMatched = 0
    var ambiguous = 0
    var unmatched = 0
    var failed = 0
    var cancelled = false
    var examples: [String] = []

    var display: String {
        "新增匹配 \(matched) · 已匹配 \(alreadyMatched) · 多重候选 \(ambiguous) · 未匹配 \(unmatched) · 失败 \(failed)" + (cancelled ? " · 已取消" : "")
    }
}

struct DuplicateGroup: Identifiable, Sendable {
    let id: String // SHA-256 of the actual bytes
    var trackIDs: [UUID]
    let fileSize: Int64

    var reclaimableBytes: Int64 { Int64(max(0, trackIDs.count - 1)) * fileSize }
}

struct DuplicateReport: Sendable {
    var groups: [DuplicateGroup] = []
    var hashes: [UUID: String] = [:]
    var failed: Int = 0
    var completed = true

    var reclaimableBytes: Int64 { groups.reduce(0) { $0 + $1.reclaimableBytes } }
}

struct LibraryScanResult: Sendable {
    let tracks: [MusicTrack]
    let storage: LibraryStorage
    let report: ScanReport
    let completed: Bool
}

enum LibraryWorkResult: Sendable {
    case scan(LibraryScanResult)
    case imported(ImportReport)
    case lyrics(LyricsMatchReport)
    case duplicates(DuplicateReport)
    case deleted(UUID, String?) // track id, optional error
}
