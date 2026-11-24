import Foundation
import CryptoKit

/// Runs inside a detached task. Uses staging files, stream copying and content hashes.
enum LibraryImportWorker {
    private struct SourceEntry {
        let url: URL
        let destinationFolder: URL
        let size: Int64
    }
    private struct Candidate {
        let url: URL
        let size: Int64
    }

    static func run(inputs: [URL], documents: URL, music: URL,
                    cachedTracks: [MusicTrack], progress: (LibraryProgress) -> Void) -> ImportReport {
        let fm = FileManager.default
        var report = ImportReport()
        var acquired: [URL] = []
        for input in inputs {
            if input.startAccessingSecurityScopedResource() { acquired.append(input) }
        }
        defer { acquired.forEach { $0.stopAccessingSecurityScopedResource() } }

        let tempRoot = fm.temporaryDirectory.appendingPathComponent("HongdaPlayerImport-\(UUID().uuidString)", isDirectory: true)
        do { try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true) }
        catch {
            report.failed += 1
            report.errors.append(error.localizedDescription)
            return report
        }
        defer { try? fm.removeItem(at: tempRoot) }

        var files: [SourceEntry] = []
        for input in inputs {
            if Task<Never, Never>.isCancelled { report.cancelled = true; return report }
            if LibraryFileRules.contains(input, in: documents),
               !(LibraryFileRules.relativePath(of: input, in: documents) ?? "").hasPrefix("Inbox/") {
                report.alreadyInLibrary += 1
                continue
            }
            do {
                let isDirectory = (try input.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true
                if isDirectory {
                    let base = music.appendingPathComponent(input.lastPathComponent, isDirectory: true)
                    guard let enumeration = fm.enumerator(at: input,
                        includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
                        options: [.skipsHiddenFiles], errorHandler: { _, _ in true }) else {
                        throw ImportError.cannotEnumerate
                    }
                    for case let file as URL in enumeration {
                        if Task<Never, Never>.isCancelled { report.cancelled = true; return report }
                        let props = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
                        guard props?.isRegularFile == true, props?.isSymbolicLink != true,
                              LibraryFileRules.acceptedExtensions.contains(file.pathExtension.lowercased()),
                              let relative = LibraryFileRules.relativePath(of: file, in: input) else { continue }
                        let subfolder = (relative as NSString).deletingLastPathComponent
                        let folder = subfolder == "" ? base : base.appendingPathComponent(subfolder, isDirectory: true)
                        files.append(SourceEntry(url: file, destinationFolder: folder,
                                                 size: Int64(props?.fileSize ?? 0)))
                    }
                } else if LibraryFileRules.acceptedExtensions.contains(input.pathExtension.lowercased()) {
                    let size = (try? input.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
                    files.append(SourceEntry(url: input, destinationFolder: music, size: size))
                }
            } catch {
                report.failed += 1
                if report.errors.count < 5 { report.errors.append("\(input.lastPathComponent): \(error.localizedDescription)") }
            }
        }

        files.sort { $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending }
        let totalBytes = files.reduce(Int64(0)) { $0 + max(0, $1.size) }
        var readBytes: Int64 = 0
        var scannedFiles = 0
        var hashedCache: [String: String] = [:]
        var known: [Int64: [Candidate]] = [:]

        // Files transferred via Finder aren't necessarily in the previous JSON catalog.
        if let enumeration = fm.enumerator(at: documents, includingPropertiesForKeys: [.fileSizeKey, .isSymbolicLinkKey],
                                           options: [.skipsHiddenFiles]) {
            for case let url as URL in enumeration where url.pathExtension.lowercased() == "flac" {
                guard LibraryFileRules.contains(url, in: documents),
                      !(LibraryFileRules.relativePath(of: url, in: documents) ?? "").hasPrefix("Inbox/"),
                      (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else { continue }
                let size = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                known[size, default: []].append(Candidate(url: url, size: size))
            }
        }
        for cached in cachedTracks {
            guard let digest = cached.sha256 else { continue }
            let path = documents.appendingPathComponent(cached.relativePath)
            let stat = try? path.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            if Int64(stat?.fileSize ?? -1) == cached.fileSize,
               let saved = cached.modifiedAt, let actual = stat?.contentModificationDate?.timeIntervalSince1970,
               abs(saved - actual) < 0.000_01 {
                hashedCache[path.path] = digest
            }
        }

        var mapping: [String: URL] = [:] // source stem (full URL path) -> imported or existing audio
        var completedSources: Set<String> = []
        func mappingKey(_ url: URL) -> String {
            LibraryFileRules.normalizedStem(url.deletingPathExtension().standardizedFileURL.path)
        }
        func tick(_ name: String) {
            progress(LibraryProgress(title: "导入音乐", detail: "\(name)（\(scannedFiles)/\(files.count)）",
                                     completed: totalBytes > 0 ? min(readBytes, totalBytes) : Int64(scannedFiles),
                                     total: totalBytes > 0 ? totalBytes : Int64(files.count)))
        }
        tick("准备导入")
        // First import FLAC so LRC files can follow the final path after name collision/duplicate handling.
        for entry in files where entry.url.pathExtension.lowercased() == "flac" {
            if Task<Never, Never>.isCancelled { report.cancelled = true; break }
            let stage = tempRoot.appendingPathComponent(UUID().uuidString + ".part")
            defer { try? fm.removeItem(at: stage) }
            do {
                let digest = try copyWithDigest(from: entry.url, to: stage) { bytes in
                    readBytes += bytes
                    if readBytes % (4 * 1_048_576) < 1_048_576 { tick(entry.url.lastPathComponent) }
                }
                try Task<Never, Never>.checkCancellation()
                let actualSize = Int64((try stage.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0)
                guard actualSize > 4 else { throw ImportError.emptyAudio }
                var duplicate: URL?
                for candidate in known[actualSize] ?? [] {
                    let knownDigest: String
                    if let cached = hashedCache[candidate.url.path] { knownDigest = cached }
                    else {
                        knownDigest = try FileDigest.sha256(of: candidate.url)
                        hashedCache[candidate.url.path] = knownDigest
                    }
                    if knownDigest == digest { duplicate = candidate.url; break }
                }
                if let duplicate {
                    mapping[mappingKey(entry.url)] = duplicate
                    report.skippedDuplicates += 1
                    completedSources.insert(entry.url.standardizedFileURL.path)
                } else {
                    try fm.createDirectory(at: entry.destinationFolder, withIntermediateDirectories: true)
                    let name = entry.url.deletingPathExtension().lastPathComponent
                    let destination = uniqueURL(in: entry.destinationFolder, stem: name, ext: "flac", fm: fm)
                    if destination.lastPathComponent != "\(name).flac" { report.conflicts += 1 }
                    try fm.moveItem(at: stage, to: destination)
                    mapping[mappingKey(entry.url)] = destination
                    known[actualSize, default: []].append(Candidate(url: destination, size: actualSize))
                    hashedCache[destination.path] = digest
                    report.importedAudio += 1
                    completedSources.insert(entry.url.standardizedFileURL.path)
                }
            } catch is CancellationError {
                report.cancelled = true
                break
            } catch {
                report.failed += 1
                if report.errors.count < 5 { report.errors.append("\(entry.url.lastPathComponent): \(error.localizedDescription)") }
            }
            scannedFiles += 1
            tick(entry.url.lastPathComponent)
        }
        if !report.cancelled {
            for entry in files where entry.url.pathExtension.lowercased() == "lrc" {
                if Task<Never, Never>.isCancelled { report.cancelled = true; break }
                let stage = tempRoot.appendingPathComponent(UUID().uuidString + ".part")
                defer { try? fm.removeItem(at: stage) }
                do {
                    _ = try copyWithDigest(from: entry.url, to: stage) { bytes in
                        readBytes += bytes
                        if readBytes % (4 * 1_048_576) < 1_048_576 { tick(entry.url.lastPathComponent) }
                    }
                    try Task<Never, Never>.checkCancellation()
                    let target: URL
                    if let pairedAudio = mapping[mappingKey(entry.url)] {
                        target = pairedAudio.deletingPathExtension().appendingPathExtension("lrc")
                    } else {
                        target = entry.destinationFolder.appendingPathComponent(
                            entry.url.deletingPathExtension().lastPathComponent).appendingPathExtension("lrc")
                    }
                    try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                    if fm.fileExists(atPath: target.path) {
                        let oldHash = try FileDigest.sha256(of: target)
                        let newHash = try FileDigest.sha256(of: stage)
                        if oldHash == newHash {
                            completedSources.insert(entry.url.standardizedFileURL.path)
                            // Same lyrics are already imported.
                        } else {
                            // Never replace existing lyrics without explicit user approval.
                            report.conflicts += 1
                            let extra = uniqueURL(in: target.deletingLastPathComponent(),
                                stem: target.deletingPathExtension().lastPathComponent, ext: "lrc", fm: fm)
                            try fm.moveItem(at: stage, to: extra)
                            report.importedLyrics += 1
                            completedSources.insert(entry.url.standardizedFileURL.path)
                        }
                    } else {
                        try fm.moveItem(at: stage, to: target)
                        report.importedLyrics += 1
                        completedSources.insert(entry.url.standardizedFileURL.path)
                    }
                } catch is CancellationError {
                    report.cancelled = true
                    break
                } catch {
                    report.failed += 1
                    if report.errors.count < 5 { report.errors.append("\(entry.url.lastPathComponent): \(error.localizedDescription)") }
                }
                scannedFiles += 1
                tick(entry.url.lastPathComponent)
            }
        }
        // Files delivered by iOS "Open in..." may be placed in Documents/Inbox.
        // Remove only successfully handled app-owned Inbox files; otherwise they'd occupy space twice.
        let inbox = documents.appendingPathComponent("Inbox", isDirectory: true)
        for path in completedSources {
            let url = URL(fileURLWithPath: path)
            if LibraryFileRules.contains(url, in: inbox) {
                try? fm.removeItem(at: url)
            }
        }
        tick(report.cancelled ? "导入已取消" : "导入完成")
        return report
    }

    private static func uniqueURL(in folder: URL, stem: String, ext: String, fm: FileManager) -> URL {
        var index = 1
        while true {
            let path = folder.appendingPathComponent(LibraryFileRules.collisionName(base: stem, ext: ext, index: index))
            if !fm.fileExists(atPath: path.path) { return path }
            index += 1
        }
    }

    /// Coordinated input read supports iCloud / third-party document providers.
    /// Outputs to an unindexed temporary file and commits with a same-volume move.
    private static func copyWithDigest(from source: URL, to temp: URL,
                                       onBytes: (Int64) -> Void) throws -> String {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordError: NSError?
        var bodyError: Error?
        var result: String?
        coordinator.coordinate(readingItemAt: source, options: [], error: &coordError) { readable in
            do {
                guard FileManager.default.createFile(atPath: temp.path, contents: nil) else {
                    throw ImportError.cannotCreateTemp
                }
                let input = try FileHandle(forReadingFrom: readable)
                defer { try? input.close() }
                let output = try FileHandle(forWritingTo: temp)
                defer { try? output.close() }
                var hash = SHA256()
                while let chunk = try input.read(upToCount: 1_048_576), !chunk.isEmpty {
                    try Task<Never, Never>.checkCancellation()
                    try output.write(contentsOf: chunk)
                    hash.update(data: chunk)
                    onBytes(Int64(chunk.count))
                }
                result = hash.finalize().map { String(format: "%02x", $0) }.joined()
            } catch { bodyError = error }
        }
        if let coordError { throw coordError }
        if let bodyError { throw bodyError }
        guard let result else { throw ImportError.cannotCreateTemp }
        return result
    }

    private enum ImportError: LocalizedError {
        case cannotEnumerate, cannotCreateTemp, emptyAudio
        var errorDescription: String? {
            switch self {
            case .cannotEnumerate: return "无法枚举所选文件夹，请确认‘文件’提供商允许访问。"
            case .cannotCreateTemp: return "无法创建导入临时文件，可能是存储空间不足。"
            case .emptyAudio: return "FLAC 文件为空或不完整。"
            }
        }
    }
}
