import XCTest
@testable import HongdaPlayer

final class LibraryManagementTests: XCTestCase {
    private var root: URL!
    private var documents: URL!
    private var music: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("flac-tests-\(UUID().uuidString)")
        documents = root.appendingPathComponent("Documents")
        music = documents.appendingPathComponent("Music")
        try FileManager.default.createDirectory(at: music, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    private func write(_ name: String, into folder: URL, text: String) throws -> URL {
        let url = folder.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        return url
    }

    private func track(_ path: String, size: Int64, title: String? = nil) -> MusicTrack {
        MusicTrack(id: UUID(), relativePath: path, title: title ?? (path as NSString).lastPathComponent,
                   artist: "歌手", album: "专辑", albumArtist: "歌手",
                   duration: 120, sampleRate: 44_100, bitDepth: 16, channels: 2,
                   artworkFile: nil, fileSize: size)
    }

    func testLegacyCatalogDecodingKeepsOldUUID() throws {
        let id = UUID()
        let original = track("Music/demo.flac", size: 1)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        object["id"] = id.uuidString
        object.removeValue(forKey: "modifiedAt")
        object.removeValue(forKey: "sha256")
        let data = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(MusicTrack.self, from: data)
        XCTAssertEqual(decoded.id, id)
        XCTAssertNil(decoded.modifiedAt)
        XCTAssertNil(decoded.sha256)
    }

    func testFolderImportCollisionAndHashDeduplication() throws {
        let source = root.appendingPathComponent("Incoming/Artist")
        let album = source.appendingPathComponent("Album")
        _ = try write("song.flac", into: album, text: String(repeating: "a", count: 4096))
        _ = try write("song.lrc", into: album, text: "[00:01.00]歌词")
        let progress: (LibraryProgress) -> Void = { _ in }
        let first = LibraryImportWorker.run(inputs: [source], documents: documents, music: music,
                                            cachedTracks: [], progress: progress)
        XCTAssertEqual(first.importedAudio, 1)
        XCTAssertEqual(first.importedLyrics, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: music.appendingPathComponent("Artist/Album/song.lrc").path))

        let second = LibraryImportWorker.run(inputs: [source], documents: documents, music: music,
                                             cachedTracks: [], progress: progress)
        XCTAssertEqual(second.importedAudio, 0)
        XCTAssertEqual(second.skippedDuplicates, 1)

        _ = try write("song.flac", into: album, text: String(repeating: "b", count: 4096))
        let third = LibraryImportWorker.run(inputs: [source], documents: documents, music: music,
                                            cachedTracks: [], progress: progress)
        XCTAssertEqual(third.importedAudio, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: music.appendingPathComponent("Artist/Album/song (2).flac").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: music.appendingPathComponent("Artist/Album/song (2).lrc").path))
    }

    func testBatchLyricsMatchAndDeleteWithoutTouchingOtherSongs() throws {
        let album = music.appendingPathComponent("An Album")
        let song = try write("hello.flac", into: album, text: String(repeating: "c", count: 1234))
        let other = try write("other.flac", into: album, text: String(repeating: "d", count: 2345))
        _ = try write("hello.lrc", into: music.appendingPathComponent("LyricsInbox"), text: "[00:01.00]Hello")
        let first = track("Music/An Album/hello.flac", size: 1234, title: "Hello")
        let second = track("Music/An Album/other.flac", size: 2345)
        let report = LyricsMatchingWorker.run(documents: documents, tracks: [first, second], progress: { _ in })
        XCTAssertEqual(report.matched, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: song.deletingPathExtension().appendingPathExtension("lrc").path))
        XCTAssertNil(SongDeletionWorker.delete(first, documents: documents))
        XCTAssertFalse(FileManager.default.fileExists(atPath: song.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: song.deletingPathExtension().appendingPathExtension("lrc").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: other.path))
    }

    func testUniqueMatcherRejectsAmbiguity() {
        let a = UUID(), b = UUID()
        XCTAssertNil(LibraryFileRules.uniqueMatch(lyricStem: "intro", trackStems: ["intro": [a, b]], titles: [:]))
        XCTAssertEqual(LibraryFileRules.uniqueMatch(lyricStem: "晴天", trackStems: [:], titles: ["晴天": [a]]), a)
    }
}
