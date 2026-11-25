import Foundation
import Observation
import UIKit
import ImageIO

/// Offline catalog and UI-facing coordinator. Expensive work runs off the main actor.
@MainActor
@Observable
final class MusicLibrary {
    private(set) var tracks: [MusicTrack] = []
    private(set) var playlists: [MusicPlaylist] = []
    private(set) var storage = LibraryStorage()
    private(set) var duplicateGroups: [DuplicateGroup] = []
    private(set) var progress: LibraryProgress?
    private(set) var isWorking = false
    private(set) var lastScan: ScanReport?
    private(set) var lastImport: ImportReport?
    private(set) var lastLyricMatch: LyricsMatchReport?
    var lastError: String?
    /// Invalidate SwiftUI cover views and refresh system Now Playing artwork.
    private(set) var artworkRevision = 0

    private let fm = FileManager.default
    let documentsURL: URL
    let musicURL: URL
    private let supportURL: URL
    private let artworkURL: URL
    private let manualArtworkURL: URL
    private let artworkCache = NSCache<NSString, UIImage>()
    private var operation: Task<Void, Never>?
    private var pendingRefresh = false
    private var pendingImports: [URL] = []

    init() {
        documentsURL = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        musicURL = documentsURL.appendingPathComponent("Music", isDirectory: true)
        supportURL = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HongdaPlayer", isDirectory: true)
        artworkURL = supportURL.appendingPathComponent("Covers", isDirectory: true)
        manualArtworkURL = artworkURL.appendingPathComponent("Manual", isDirectory: true)
        artworkCache.totalCostLimit = 32 * 1024 * 1024  // decoded pixels, not file bytes
        artworkCache.countLimit = 24
        do {
            try fm.createDirectory(at: musicURL, withIntermediateDirectories: true)
            try fm.createDirectory(at: manualArtworkURL, withIntermediateDirectories: true)
            playlists = readJSON([MusicPlaylist].self, file: "playlists.json") ?? []
            tracks = readJSON([MusicTrack].self, file: "catalog.json") ?? []
            refresh()
        } catch { lastError = "无法创建音乐目录：\(error.localizedDescription)" }
    }

    private func readJSON<T: Decodable>(_ type: T.Type, file: String) -> T? {
        let path = supportURL.appendingPathComponent(file)
        guard let data = try? Data(contentsOf: path) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func writeJSON<T: Encodable>(_ value: T, file: String) {
        do {
            let data = try JSONEncoder().encode(value)
            try data.write(to: supportURL.appendingPathComponent(file), options: .atomic)
        } catch { lastError = "保存资料库失败：\(error.localizedDescription)" }
    }

    func fileURL(for track: MusicTrack) -> URL {
        documentsURL.appendingPathComponent(track.relativePath)
    }

    func lyricsURL(for track: MusicTrack) -> URL? {
        let file = fileURL(for: track).deletingPathExtension().appendingPathExtension("lrc")
        if fm.fileExists(atPath: file.path) { return file }
        let sharedLyrics = musicURL.appendingPathComponent(file.lastPathComponent)
        guard fm.fileExists(atPath: sharedLyrics.path) else { return nil }
        // Avoid applying one root-level LRC to several identically named songs.
        let key = LibraryFileRules.normalizedStem(file.deletingPathExtension().lastPathComponent)
        let candidates = tracks.filter {
            LibraryFileRules.normalizedStem(fileURL(for: $0).deletingPathExtension().lastPathComponent) == key
        }
        return candidates.count == 1 ? sharedLyrics : nil
    }

    private func manualCoverURL(for id: UUID) -> URL {
        manualArtworkURL.appendingPathComponent("\(id.uuidString).jpg")
    }

    func hasCustomArtwork(for track: MusicTrack) -> Bool {
        fm.fileExists(atPath: manualCoverURL(for: track.id).path)
    }

    func artwork(for track: MusicTrack) -> UIImage? {
        let manual = manualCoverURL(for: track.id)
        let path: URL
        if fm.fileExists(atPath: manual.path) {
            path = manual
        } else if let filename = track.artworkFile {
            path = artworkURL.appendingPathComponent(filename)
        } else {
            return nil
        }
        let key = path.path as NSString
        if let cached = artworkCache.object(forKey: key) { return cached }
        // Downsample to avoid decoding 3000x3000 artwork (36 MB+) for tiny thumbnails.
        guard let image = LocalArtworkProcessor.thumbnail(at: path) else { return nil }
        let estimatedBytes = (image.cgImage?.bytesPerRow ?? 0) * (image.cgImage?.height ?? 0)
        artworkCache.setObject(image, forKey: key, cost: estimatedBytes)
        return image
    }

    /// Stores a per-song cover override WITHOUT changing original FLAC metadata.
    /// It survives an incremental rescan and can be removed to reveal embedded art.
    func setCustomArtwork(_ data: Data, for track: MusicTrack) async {
        do {
            let converted = try await Task.detached(priority: .userInitiated) {
                try LocalArtworkProcessor.normalizedJPEG(data)
            }.value
            guard tracks.contains(where: { $0.id == track.id }) else { return }
            let path = manualCoverURL(for: track.id)
            let oldSize = (try? path.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            try converted.write(to: path, options: .atomic)
            artworkCache.removeObject(forKey: path.path as NSString)
            storage.artworkBytes += Int64(converted.count - oldSize)
            artworkRevision &+= 1
        } catch {
            lastError = "无法保存封面：\(error.localizedDescription)"
        }
    }

    func removeCustomArtwork(for track: MusicTrack) {
        let path = manualCoverURL(for: track.id)
        let bytes = (try? path.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        do {
            if fm.fileExists(atPath: path.path) { try fm.removeItem(at: path) }
            artworkCache.removeObject(forKey: path.path as NSString)
            storage.artworkBytes = max(0, storage.artworkBytes - Int64(bytes))
            artworkRevision &+= 1
        } catch {
            lastError = "无法恢复默认封面：\(error.localizedDescription)"
        }
    }

    private func manualArtworkBytes() -> Int64 {
        let items = (try? fm.contentsOfDirectory(at: manualArtworkURL,
                        includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return items.reduce(Int64(0)) { sum, url in
            sum + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }

    /// Finder/AirDrop changes are observed when the app becomes active. Scans serialize with mutations.
    func refresh() {
        guard !isWorking else {
            if progress?.title != "增量扫描" { pendingRefresh = true }
            return
        }
        let documents = documentsURL
        let music = musicURL
        let covers = artworkURL
        let existing = tracks
        start("增量扫描") { update in
            .scan(LibraryIndexer.scan(documents: documents, music: music, covers: covers,
                                      existing: existing, progress: update))
        }
    }

    func importFiles(_ urls: [URL]) { startImport(urls) }
    func importFolders(_ urls: [URL]) { startImport(urls) }

    private func startImport(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        if isWorking {
            pendingImports.append(contentsOf: urls)
            return
        }
        let documents = documentsURL
        let music = musicURL
        let cached = tracks
        start("导入音乐") { update in
            .imported(LibraryImportWorker.run(inputs: urls, documents: documents, music: music,
                                              cachedTracks: cached, progress: update))
        }
    }

    func matchLyrics() {
        let documents = documentsURL
        let existing = tracks
        start("批量匹配 LRC") { update in
            .lyrics(LyricsMatchingWorker.run(documents: documents, tracks: existing, progress: update))
        }
    }

    func detectDuplicates() {
        let documents = documentsURL
        let existing = tracks
        start("检测重复歌曲") { update in
            .duplicates(DuplicateDetectionWorker.run(documents: documents, tracks: existing,
                                                      progress: update))
        }
    }

    /// Caller should stop playback first, then request removal of the audio + same-folder LRC.
    func deleteSong(_ song: MusicTrack) {
        let documents = documentsURL
        start("删除歌曲") { _ in
            .deleted(song.id, SongDeletionWorker.delete(song, documents: documents))
        }
    }

    func cancelOperation() {
        pendingImports.removeAll()
        operation?.cancel()
    }

    private func start(_ title: String,
                       work: @escaping @Sendable (@escaping @Sendable (LibraryProgress) -> Void) -> LibraryWorkResult) {
        guard !isWorking else {
            lastError = "文件管理正在执行其他任务，请先完成或取消当前操作。"
            return
        }
        isWorking = true
        progress = LibraryProgress(title: title)
        operation = Task.detached(priority: .utility) { [weak self] in
            let outcome = work { [weak self] event in
                Task { @MainActor [weak self] in
                    if self?.isWorking == true { self?.progress = event }
                }
            }
            await MainActor.run { [weak self] in self?.finish(outcome) }
        }
    }

    private func finish(_ outcome: LibraryWorkResult) {
        switch outcome {
        case .scan(let result):
            if result.completed {
                let previouslyUsed = Set(tracks.compactMap(\.artworkFile))
                tracks = result.tracks
                storage = result.storage
                storage.artworkBytes += manualArtworkBytes()
                lastScan = result.report
                artworkCache.removeAllObjects()
                let retained = Set(tracks.compactMap(\.artworkFile))
                for image in previouslyUsed.subtracting(retained) {
                    try? fm.removeItem(at: artworkURL.appendingPathComponent(image))
                }
                // Also clean orphaned extracted covers from an interrupted earlier scan.
                if let covers = try? fm.contentsOfDirectory(at: artworkURL,
                                                includingPropertiesForKeys: nil) {
                    for cover in covers where cover.pathExtension.lowercased() == "art" &&
                        !retained.contains(cover.lastPathComponent) {
                        try? fm.removeItem(at: cover)
                    }
                }
                let ids = Set(tracks.map(\.id))
                for index in playlists.indices {
                    playlists[index].trackIDs.removeAll { !ids.contains($0) }
                }
                duplicateGroups = [] // hashes must be refreshed after external edits
                writeJSON(tracks, file: "catalog.json")
                writeJSON(playlists, file: "playlists.json")
            }
        case .imported(let result):
            lastImport = result
            pendingRefresh = true
            if result.failed > 0 { lastError = result.errors.prefix(3).joined(separator: "\n") }
        case .lyrics(let result):
            lastLyricMatch = result
            pendingRefresh = true
        case .duplicates(let result):
            guard result.completed else {
                lastError = "重复检测已取消，保留上次完整检测结果。"
                break
            }
            for index in tracks.indices {
                if let hash = result.hashes[tracks[index].id] { tracks[index].sha256 = hash }
            }
            duplicateGroups = result.groups
            writeJSON(tracks, file: "catalog.json")
            if result.failed > 0 { lastError = "有 \(result.failed) 个文件无法完成哈希校验。" }
        case .deleted(let id, let error):
            if let error { lastError = error }
            else {
                AppPreferences.removeLyricOffset(for: id)
                let manual = manualCoverURL(for: id)
                try? fm.removeItem(at: manual)
                artworkCache.removeObject(forKey: manual.path as NSString)
                artworkRevision &+= 1
            }
            pendingRefresh = true
        }
        operation = nil
        progress = nil
        isWorking = false
        if !pendingImports.isEmpty {
            let next = pendingImports
            pendingImports.removeAll()
            startImport(next)
        } else if pendingRefresh {
            pendingRefresh = false
            refresh()
        }
    }

    func createPlaylist(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        playlists.append(MusicPlaylist(name: trimmed))
        writeJSON(playlists, file: "playlists.json")
    }

    func add(track: MusicTrack, to playlistID: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        if !playlists[index].trackIDs.contains(track.id) {
            playlists[index].trackIDs.append(track.id)
            writeJSON(playlists, file: "playlists.json")
        }
    }

    func remove(track: MusicTrack, from playlistID: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        playlists[index].trackIDs.removeAll { $0 == track.id }
        writeJSON(playlists, file: "playlists.json")
    }

    func deletePlaylist(_ id: UUID) {
        playlists.removeAll { $0.id == id }
        writeJSON(playlists, file: "playlists.json")
    }

    func tracks(in playlist: MusicPlaylist) -> [MusicTrack] {
        let lookup = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
        return playlist.trackIDs.compactMap { lookup[$0] }
    }
}


/// ImageIO decoding is performed on the worker thread for user-selected artwork.
/// Only a <=1024px preview is ever cached on the UI thread.
private enum LocalArtworkProcessor {
    enum Error: LocalizedError {
        case emptyOrOversized
        case unsupported
        var errorDescription: String? {
            switch self {
            case .emptyOrOversized: return "图片为空，或超过 25 MB 的导入上限"
            case .unsupported: return "不是可识别的图片格式"
            }
        }
    }

    static func thumbnail(at file: URL) -> UIImage? {
        // Embedded FLAC artwork uses a .art extension; decode by file bytes,
        // not by path extension, so JPEG/PNG cover metadata keeps working.
        guard let bytes = try? Data(contentsOf: file, options: .mappedIfSafe),
              let source = CGImageSourceCreateWithData(bytes as CFData, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1024,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }

    static func normalizedJPEG(_ bytes: Data) throws -> Data {
        guard !bytes.isEmpty, bytes.count <= 25 * 1024 * 1024 else {
            throw Error.emptyOrOversized
        }
        guard let source = CGImageSourceCreateWithData(bytes as CFData, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1024,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary),
              let jpeg = UIImage(cgImage: cg).jpegData(compressionQuality: 0.90) else {
            throw Error.unsupported
        }
        return jpeg
    }
}
