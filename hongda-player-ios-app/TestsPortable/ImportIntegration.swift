import Foundation
func write(_ url: URL, _ text: String) throws {
  try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
  try Data(text.utf8).write(to: url)
}
func check(_ value: @autoclosure () -> Bool, _ explanation: String) {
  if !value() { fputs("FAIL: \(explanation)\n", stderr); exit(2) }
  print("PASS: \(explanation)")
}
@main
struct TestMain {
 static func main() throws {
  let fm = FileManager.default
  let root = fm.temporaryDirectory.appendingPathComponent("hongdakuaibo-integration-"+UUID().uuidString)
  defer { try? fm.removeItem(at: root) }
  let docs = root.appendingPathComponent("Documents")
  let music = docs.appendingPathComponent("Music")
  let folder = root.appendingPathComponent("outside/Artist")
  let album = folder.appendingPathComponent("Album")
  try fm.createDirectory(at: music, withIntermediateDirectories: true)
  try write(album.appendingPathComponent("one.flac"), String(repeating:"A",count:4096))
  try write(album.appendingPathComponent("one.lrc"), "[00:01.00]第一句")
  try write(album.appendingPathComponent("two.flac"), String(repeating:"B",count:4096))
  let progress: (LibraryProgress)->Void = {_ in}
  let r1 = LibraryImportWorker.run(inputs:[folder],documents:docs,music:music,cachedTracks:[],progress:progress)
  check(r1.importedAudio == 2 && r1.importedLyrics == 1, "Folder import copied 2 songs and paired lyric")
  let copied = music.appendingPathComponent("Artist/Album/one.flac")
  check(fm.fileExists(atPath: copied.path), "Folder hierarchy preserved")
  check(fm.fileExists(atPath: music.appendingPathComponent("Artist/Album/one.lrc").path), "Same-folder LRC preserved")
  let r2 = LibraryImportWorker.run(inputs:[folder],documents:docs,music:music,cachedTracks:[],progress:progress)
  check(r2.skippedDuplicates == 2 && r2.importedAudio == 0, "Repeated content skipped via digest")
  try write(album.appendingPathComponent("one.flac"),String(repeating:"C",count:4096))
  let r3 = LibraryImportWorker.run(inputs:[folder],documents:docs,music:music,cachedTracks:[],progress:progress)
  check(r3.importedAudio == 1 && r3.conflicts >= 1, "Same name with new contents gets suffix")
  check(fm.fileExists(atPath: music.appendingPathComponent("Artist/Album/one (2).flac").path),"Renamed FLAC exists")
  check(fm.fileExists(atPath: music.appendingPathComponent("Artist/Album/one (2).lrc").path),"Renamed FLAC also receives corresponding LRC")
  // Build lightweight test tracks from file URLs (audio validity is not needed for import tests).
  let paths = ["Music/Artist/Album/one.flac","Music/Artist/Album/one (2).flac","Music/Artist/Album/two.flac"]
  let tracks = paths.map { path in
    MusicTrack(id:UUID(),relativePath:path,title:URL(fileURLWithPath:path).deletingPathExtension().lastPathComponent,
               artist:"X",album:"Y",albumArtist:"X",duration:100,sampleRate:44100,bitDepth:16,
               channels:2,artworkFile:nil,fileSize:4096)
  }
  let sourceLyric = root.appendingPathComponent("outside/standalone/two.lrc")
  try write(sourceLyric,"[00:02.00]Second")
  let r4 = LibraryImportWorker.run(inputs:[sourceLyric],documents:docs,music:music,cachedTracks:[],progress:progress)
  check(r4.importedLyrics == 1,"Standalone lyric imported")
  let matched = LyricsMatchingWorker.run(documents:docs,tracks:tracks,progress:progress)
  check(matched.matched >= 1,"Batch matching attaches unique basename LRC")
  check(fm.fileExists(atPath: music.appendingPathComponent("Artist/Album/two.lrc").path),"Matched lyric placed next to track")
  let extra = music.appendingPathComponent("Copies/duplicate.flac")
  try fm.createDirectory(at: extra.deletingLastPathComponent(),withIntermediateDirectories:true)
  try fm.copyItem(at:copied,to:extra)
  let more = MusicTrack(id:UUID(),relativePath:"Music/Copies/duplicate.flac",title:"Copy",artist:"X",album:"Y",albumArtist:"X",duration:100,sampleRate:44100,bitDepth:16,channels:2,artworkFile:nil,fileSize:4096)
  let d = DuplicateDetectionWorker.run(documents:docs,tracks:tracks+[more],progress:progress)
  check(d.groups.count == 1 && d.groups.first?.trackIDs.count == 2,"Same-size content duplicates detected by SHA")
  check(d.reclaimableBytes == 4096,"Reclaimable bytes computed")
  let deleteError = SongDeletionWorker.delete(more,documents:docs)
  check(deleteError == nil && !fm.fileExists(atPath:extra.path), "Delete removes only selected duplicate")
  check(fm.fileExists(atPath:copied.path),"Original song remains")
  check(LibraryFileRules.uniqueMatch(lyricStem:"One",trackStems:["one":[tracks[0].id]],titles:[:])==tracks[0].id,"Case insensitive unique stem match")
  check(LibraryFileRules.uniqueMatch(lyricStem:"same",trackStems:["same":[tracks[0].id,tracks[1].id]],titles:[:]) == nil,"Ambiguous stem not auto matched")
  print("ALL FILE MANAGEMENT INTEGRATION TESTS PASSED")
 }
}
