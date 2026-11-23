import Foundation

/// Explicit batch matching. Only unique filename/title candidates are copied next to a song.
enum LyricsMatchingWorker {
    static func run(documents: URL, tracks: [MusicTrack],
                    progress: (LibraryProgress) -> Void) -> LyricsMatchReport {
        let fm = FileManager.default
        var result = LyricsMatchReport()
        let directSidecars = Set(tracks.map {
            documents.appendingPathComponent($0.relativePath)
                .deletingPathExtension().appendingPathExtension("lrc")
                .standardizedFileURL.path.lowercased()
        })
        var byStem: [String: [UUID]] = [:]
        var byTitle: [String: [UUID]] = [:]
        let tracksByID = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
        for track in tracks {
            let stem = LibraryFileRules.normalizedStem(
                URL(fileURLWithPath: track.relativePath).deletingPathExtension().lastPathComponent)
            byStem[stem, default: []].append(track.id)
            byTitle[LibraryFileRules.normalizedStem(track.title), default: []].append(track.id)
        }
        guard let enumeration = fm.enumerator(at: documents,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]) else { result.failed += 1; return result }
        var lyrics: [URL] = []
        for case let url as URL in enumeration where url.pathExtension.lowercased() == "lrc" {
            guard LibraryFileRules.contains(url, in: documents),
                  !(LibraryFileRules.relativePath(of: url, in: documents) ?? "").hasPrefix("Inbox/"),
                  (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else { continue }
            lyrics.append(url)
        }
        for (index, lyric) in lyrics.enumerated() {
            if Task<Never, Never>.isCancelled { result.cancelled = true; break }
            progress(LibraryProgress(title: "批量匹配 LRC", detail: lyric.lastPathComponent,
                                     completed: Int64(index), total: Int64(lyrics.count)))
            if directSidecars.contains(lyric.standardizedFileURL.path.lowercased()) {
                result.alreadyMatched += 1
                continue
            }
            let stem = lyric.deletingPathExtension().lastPathComponent
            let key = LibraryFileRules.normalizedStem(stem)
            guard let id = LibraryFileRules.uniqueMatch(lyricStem: stem,
                                                        trackStems: byStem, titles: byTitle),
                  let track = tracksByID[id] else {
                if Set(byStem[key] ?? []).count > 1 ||
                    (byStem[key] ?? []).isEmpty && Set(byTitle[key] ?? []).count > 1 {
                    result.ambiguous += 1
                } else { result.unmatched += 1 }
                if result.examples.count < 8 { result.examples.append(lyric.lastPathComponent) }
                continue
            }
            let audio = documents.appendingPathComponent(track.relativePath)
            let target = audio.deletingPathExtension().appendingPathExtension("lrc")
            if fm.fileExists(atPath: target.path) {
                result.alreadyMatched += 1
                continue
            }
            do {
                // Stage the sidecar in the same directory; moveItem publishes it atomically.
                let staging = target.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).tmp")
                defer { try? fm.removeItem(at: staging) }
                try fm.copyItem(at: lyric, to: staging)
                try Task<Never, Never>.checkCancellation()
                try fm.moveItem(at: staging, to: target)
                result.matched += 1
            } catch is CancellationError {
                result.cancelled = true
                break
            } catch {
                result.failed += 1
                if result.examples.count < 8 { result.examples.append("\(lyric.lastPathComponent): \(error.localizedDescription)") }
            }
        }
        progress(LibraryProgress(title: "批量匹配 LRC", detail: result.cancelled ? "已取消" : "匹配结束",
                                 completed: Int64(lyrics.count), total: Int64(lyrics.count)))
        return result
    }
}

/// Hash only files with equal sizes. SHA-256 is cached against file size and mtime.
enum DuplicateDetectionWorker {
    static func run(documents: URL, tracks: [MusicTrack],
                    progress: (LibraryProgress) -> Void) -> DuplicateReport {
        let fm = FileManager.default
        var result = DuplicateReport()
        let buckets = Dictionary(grouping: tracks, by: \.fileSize)
        let candidates = buckets.filter { $0.value.count > 1 }
        let total = candidates.values.reduce(0) { $0 + $1.count }
        var count = 0
        for (size, items) in candidates {
            var hashes: [String: [UUID]] = [:]
            for track in items {
                if Task<Never, Never>.isCancelled { result.completed = false; return result }
                count += 1
                progress(LibraryProgress(title: "内容重复检测", detail: track.title,
                                         completed: Int64(count), total: Int64(total)))
                let file = documents.appendingPathComponent(track.relativePath)
                guard LibraryFileRules.contains(file, in: documents), fm.fileExists(atPath: file.path),
                      (try? file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else {
                    result.failed += 1; continue
                }
                do {
                    let values = try file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                    let valid = Int64(values.fileSize ?? -1) == track.fileSize &&
                        track.modifiedAt != nil && values.contentModificationDate != nil &&
                        abs(track.modifiedAt! - values.contentModificationDate!.timeIntervalSince1970) < 0.000_01
                    let hash: String
                    if valid, let cached = track.sha256 { hash = cached }
                    else { hash = try FileDigest.sha256(of: file) }
                    result.hashes[track.id] = hash
                    hashes[hash, default: []].append(track.id)
                } catch is CancellationError { result.completed = false; return result }
                catch { result.failed += 1 }
            }
            for (hash, ids) in hashes where ids.count > 1 {
                result.groups.append(DuplicateGroup(id: hash, trackIDs: ids, fileSize: size))
            }
        }
        result.groups.sort { $0.reclaimableBytes > $1.reclaimableBytes }
        progress(LibraryProgress(title: "内容重复检测", detail: "检测完成",
                                 completed: Int64(total), total: Int64(total)))
        return result
    }
}

enum SongDeletionWorker {
    static func delete(_ track: MusicTrack, documents: URL) -> String? {
        let fm = FileManager.default
        let file = documents.appendingPathComponent(track.relativePath)
        guard LibraryFileRules.contains(file, in: documents),
              file.pathExtension.lowercased() == "flac",
              (try? file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else {
            return "文件路径不在音乐库内，已拒绝删除。"
        }
        do {
            // Removing the music and the matching same-folder sidecar is explicit in the UI.
            try fm.removeItem(at: file)
            let lyric = file.deletingPathExtension().appendingPathExtension("lrc")
            if fm.fileExists(atPath: lyric.path), LibraryFileRules.contains(lyric, in: documents),
               (try? lyric.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true {
                try fm.removeItem(at: lyric)
            }
            return nil
        } catch { return "删除失败：\(error.localizedDescription)" }
    }
}
