import Foundation

/// Called away from the main actor. Never decodes a previously indexed, unchanged file.
enum LibraryIndexer {
    static func scan(documents: URL,
                     music: URL,
                     covers: URL,
                     existing: [MusicTrack],
                     progress: (LibraryProgress) -> Void) -> LibraryScanResult {
        let fm = FileManager.default
        let old = Dictionary(uniqueKeysWithValues: existing.map { ($0.relativePath, $0) })
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey,
                                      .fileSizeKey, .contentModificationDateKey]
        var discovered: [URL] = []
        var storage = LibraryStorage()
        var report = ScanReport()
        guard let enumerator = fm.enumerator(at: documents, includingPropertiesForKeys: keys,
                                            options: [.skipsHiddenFiles], errorHandler: { url, err in
            report.failed += 1
            if report.messages.count < 5 { report.messages.append("\(url.lastPathComponent): \(err.localizedDescription)") }
            return true
        }) else {
            report.failed += 1
            report.messages.append("无法扫描 Documents")
            return LibraryScanResult(tracks: existing, storage: storage, report: report, completed: false)
        }
        for case let url as URL in enumerator {
            if Task<Never, Never>.isCancelled {
                return LibraryScanResult(tracks: existing, storage: storage, report: report, completed: false)
            }
            if !LibraryFileRules.contains(url, in: documents) { continue }
            guard let relative = LibraryFileRules.relativePath(of: url, in: documents),
                  !relative.hasPrefix("Inbox/") else { continue }
            let attributes = try? url.resourceValues(forKeys: Set(keys))
            if attributes?.isSymbolicLink == true || attributes?.isRegularFile == false { continue }
            let ext = url.pathExtension.lowercased()
            let size = Int64(attributes?.fileSize ?? 0)
            if ext == "flac" {
                storage.audioBytes += size
                discovered.append(url)
            } else if ext == "lrc" {
                storage.lyricBytes += size
                storage.lyricFiles += 1
            }
        }

        var items: [MusicTrack] = []
        let total = discovered.count
        for (i, url) in discovered.enumerated() {
            if Task<Never, Never>.isCancelled {
                return LibraryScanResult(tracks: existing, storage: storage, report: report, completed: false)
            }
            if i % 5 == 0 || i + 1 == total {
                progress(LibraryProgress(title: "增量扫描", detail: url.lastPathComponent,
                                         completed: Int64(i), total: Int64(total)))
            }
            guard let relative = LibraryFileRules.relativePath(of: url, in: documents) else { continue }
            let props = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let size = Int64(props?.fileSize ?? 0)
            let mtime = props?.contentModificationDate?.timeIntervalSince1970
            if let cached = old[relative], cached.fileSize == size,
               let oldStamp = cached.modifiedAt, let mtime,
               abs(oldStamp - mtime) < 0.000_01 {
                items.append(cached)
                report.reused += 1
                continue
            }
            do {
                let decoder = try FLACDecoder(url: url)
                let metadata = decoder.details
                let id = old[relative]?.id ?? UUID()
                var coverFilename: String?
                if let image = metadata.artwork, !image.isEmpty {
                    coverFilename = "\(id.uuidString).art"
                    try image.write(to: covers.appendingPathComponent(coverFilename!), options: .atomic)
                }
                items.append(MusicTrack(id: id, relativePath: relative,
                                        title: metadata.title ?? url.deletingPathExtension().lastPathComponent,
                                        artist: metadata.artist ?? "未知歌手",
                                        album: metadata.album ?? "未知专辑",
                                        albumArtist: metadata.albumArtist ?? metadata.artist ?? "未知歌手",
                                        duration: metadata.duration,
                                        sampleRate: metadata.sampleRate,
                                        bitDepth: metadata.bitsPerSample,
                                        channels: metadata.channels,
                                        artworkFile: coverFilename,
                                        fileSize: size,
                                        modifiedAt: mtime, sha256: nil))
                if old[relative] != nil { report.updated += 1 }
                else { report.added += 1 }
            } catch {
                report.failed += 1
                if report.messages.count < 5 {
                    report.messages.append("\(url.lastPathComponent): \(error.localizedDescription)")
                }
            }
        }
        let indexedPaths = Set(items.map(\.relativePath))
        report.removed = old.keys.filter { !indexedPaths.contains($0) }.count
        items.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        let matchedCount = items.filter { track in
            let songURL = documents.appendingPathComponent(track.relativePath)
            let sibling = songURL.deletingPathExtension().appendingPathExtension("lrc")
            let fallback = music.appendingPathComponent(sibling.lastPathComponent)
            return fm.fileExists(atPath: sibling.path) || fm.fileExists(atPath: fallback.path)
        }.count
        storage.matchedTracks = matchedCount

        // Only retained covers are counted; orphaned cover files are cleaned after scan.
        for name in Set(items.compactMap(\.artworkFile)) {
            let cover = covers.appendingPathComponent(name)
            let props = try? cover.resourceValues(forKeys: [.fileSizeKey])
            storage.artworkBytes += Int64(props?.fileSize ?? 0)
        }
        let fsAttrs = try? fm.attributesOfFileSystem(forPath: documents.path)
        storage.freeBytes = (fsAttrs?[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
        progress(LibraryProgress(title: "增量扫描", detail: "扫描完成", completed: Int64(total), total: Int64(total)))
        return LibraryScanResult(tracks: items, storage: storage, report: report, completed: true)
    }
}
