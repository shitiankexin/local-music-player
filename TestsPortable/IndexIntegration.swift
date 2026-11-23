import Foundation
@main
struct TestIndex {
 static func main() throws {
  let fm = FileManager.default
  let root = fm.temporaryDirectory.appendingPathComponent("localflac-index-"+UUID().uuidString)
  defer {try? fm.removeItem(at:root)}
  let docs=root.appendingPathComponent("Documents")
  let music=docs.appendingPathComponent("Music")
  let covers=root.appendingPathComponent("Covers")
  try fm.createDirectory(at:music,withIntermediateDirectories:true)
  try fm.createDirectory(at:covers,withIntermediateDirectories:true)
  let song = music.appendingPathComponent("abc.flac")
  try Data("AAAAAAAAA".utf8).write(to:song)
  let s1=LibraryIndexer.scan(documents:docs,music:music,covers:covers,existing:[],progress:{_ in})
  assert(s1.report.added==1 && s1.tracks.count==1 && s1.tracks.first?.modifiedAt != nil)
  let s2=LibraryIndexer.scan(documents:docs,music:music,covers:covers,existing:s1.tracks,progress:{_ in})
  assert(s2.report.reused==1 && s2.report.added==0 && s2.tracks.first?.id==s1.tracks.first?.id)
  let sidecar=music.appendingPathComponent("abc.lrc")
  try Data("[00:01.00]abc".utf8).write(to:sidecar)
  let s3=LibraryIndexer.scan(documents:docs,music:music,covers:covers,existing:s2.tracks,progress:{_ in})
  assert(s3.storage.matchedTracks==1 && s3.storage.lyricFiles==1)
  // Modify with SAME byte length but a DIFFERENT modification timestamp.
  try Data("BBBBBBBBB".utf8).write(to:song)
  try fm.setAttributes([.modificationDate:Date(timeIntervalSince1970:1000000000)],ofItemAtPath:song.path)
  let s4=LibraryIndexer.scan(documents:docs,music:music,covers:covers,existing:s3.tracks,progress:{_ in})
  assert(s4.report.updated==1 && s4.tracks.first?.id==s3.tracks.first?.id)
  try fm.removeItem(at:song)
  let s5=LibraryIndexer.scan(documents:docs,music:music,covers:covers,existing:s4.tracks,progress:{_ in})
  assert(s5.report.removed==1 && s5.tracks.isEmpty)
  print("ALL INDEXING INTEGRATION TESTS PASSED")
 }
}
