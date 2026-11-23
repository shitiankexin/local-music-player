import Foundation

struct MusicTrack: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var relativePath: String
    var title: String
    var artist: String
    var album: String
    var albumArtist: String
    var duration: TimeInterval
    var sampleRate: Int
    var bitDepth: Int
    var channels: Int
    var artworkFile: String?
    var fileSize: Int64
    // Optional for backwards-compatible decoding of the V1 catalog.
    var modifiedAt: TimeInterval? = nil
    var sha256: String? = nil

    var qualityLabel: String {
        "\(bitDepth)-bit / \(Double(sampleRate) / 1000) kHz"
    }
}

struct MusicPlaylist: Identifiable, Codable, Sendable {
    var id = UUID()
    var name: String
    var trackIDs: [UUID] = []
}
