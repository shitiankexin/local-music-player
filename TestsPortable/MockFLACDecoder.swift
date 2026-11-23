import Foundation
struct FLACDetails {
 let sampleRate: Int = 44100
 let bitsPerSample: Int = 16
 let channels: Int = 2
 let title: String? = nil
 let artist: String? = nil
 let album: String? = nil
 let albumArtist: String? = nil
 let artwork: Data? = nil
 let duration: TimeInterval = 100
}
final class FLACDecoder {
 let details = FLACDetails()
 init(url: URL) throws {
   if ((try? Data(contentsOf: url)) ?? Data()).isEmpty { throw NSError(domain:"flac",code:1) }
 }
}
