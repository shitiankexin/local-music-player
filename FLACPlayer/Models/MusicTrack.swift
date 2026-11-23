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


// MARK: - V6 lightweight song ordering (metadata only; never loads audio)
enum SongSortKey: String, CaseIterable, Codable {
    case libraryOrder, title, artist, album, duration, fileSize, modifiedAt

    var label: String {
        switch self {
        case .libraryOrder: return "默认顺序"
        case .title: return "歌曲名称"
        case .artist: return "歌手名称"
        case .album: return "专辑名称"
        case .duration: return "歌曲时长"
        case .fileSize: return "文件大小"
        case .modifiedAt: return "文件修改时间"
        }
    }

    static func ordered(_ tracks: [MusicTrack], by key: SongSortKey, ascending: Bool) -> [MusicTrack] {
        if key == .libraryOrder {
            return ascending ? tracks : Array(tracks.reversed())
        }
        // Decorate with original index to keep even completely identical metadata stable.
        return tracks.enumerated().sorted { lhs, rhs in
            let comparison: ComparisonResult
            switch key {
            case .title:
                comparison = lhs.element.title.localizedStandardCompare(rhs.element.title)
            case .artist:
                comparison = lhs.element.artist.localizedStandardCompare(rhs.element.artist)
            case .album:
                comparison = lhs.element.album.localizedStandardCompare(rhs.element.album)
            case .duration:
                comparison = compare(lhs.element.duration, rhs.element.duration)
            case .fileSize:
                comparison = compare(lhs.element.fileSize, rhs.element.fileSize)
            case .modifiedAt:
                comparison = compare(lhs.element.modifiedAt ?? 0, rhs.element.modifiedAt ?? 0)
            case .libraryOrder:
                comparison = .orderedSame
            }
            // A tie always uses the stable original index, independent of direction.
            if comparison == .orderedSame { return lhs.offset < rhs.offset }
            return ascending ? comparison == .orderedAscending : comparison == .orderedDescending
        }.map(\.element)
    }

    private static func compare<T: Comparable>(_ a: T, _ b: T) -> ComparisonResult {
        if a < b { return .orderedAscending }
        if a > b { return .orderedDescending }
        return .orderedSame
    }
}

// MARK: - V6 audio-effect settings (data only, persisted without PCM or track data)
enum AudioEQPreset: String, CaseIterable, Codable, Sendable {
    case flat, pop, bass, vocal, classical, rock, custom

    var label: String {
        switch self {
        case .flat: return "平直"
        case .pop: return "流行"
        case .bass: return "低音"
        case .vocal: return "人声"
        case .classical: return "古典"
        case .rock: return "摇滚"
        case .custom: return "自定义"
        }
    }

    var gains: [Float] {
        switch self {
        case .flat, .custom: return Array(repeating: 0, count: 10)
        case .pop: return [-1, 0, 2, 2, 0, -1, 1, 2, 2, 1]
        case .bass: return [5, 5, 4, 2, 0, 0, 0, 0, 0, 0]
        case .vocal: return [-2, -2, -1, 0, 2, 3, 3, 1, 0, -1]
        case .classical: return [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        case .rock: return [3, 3, 2, 0, -2, -1, 1, 3, 3, 2]
        }
    }
}

enum AudioReverbSpace: String, CaseIterable, Codable, Sendable {
    case smallRoom, mediumRoom, mediumHall, largeHall

    var label: String {
        switch self {
        case .smallRoom: return "小房间"
        case .mediumRoom: return "中型房间"
        case .mediumHall: return "音乐厅"
        case .largeHall: return "大厅"
        }
    }
}

struct AudioEffectsSettings: Codable, Equatable, Sendable {
    static let frequencies: [Float] = [31.25, 62.5, 125, 250, 500, 1_000, 2_000, 4_000, 8_000, 16_000]
    var enabled = false // true bypass by default; no change to original sound
    var preset = AudioEQPreset.flat
    var bands: [Float] = Array(repeating: 0, count: 10)
    var preampDB: Float = 0 // user-adjustable attenuation, -12 ... 0 dB
    var bassDB: Float = 0
    var trebleDB: Float = 0
    var reverbEnabled = false
    var reverbSpace = AudioReverbSpace.mediumHall
    var reverbMix: Float = 12 // percentage, 0 ... 40
    var balance: Float = 0 // -1 left, +1 right

    func sanitized() -> AudioEffectsSettings {
        var value = self
        if value.bands.count != Self.frequencies.count {
            value.bands = AudioEQPreset.flat.gains
            value.preset = .flat
        }
        value.bands = value.bands.map { $0.isFinite ? min(12, max(-12, $0)) : 0 }
        value.preampDB = value.preampDB.isFinite ? min(0, max(-12, value.preampDB)) : 0
        value.bassDB = value.bassDB.isFinite ? min(12, max(-12, value.bassDB)) : 0
        value.trebleDB = value.trebleDB.isFinite ? min(12, max(-12, value.trebleDB)) : 0
        value.reverbMix = value.reverbMix.isFinite ? min(40, max(0, value.reverbMix)) : 0
        value.balance = value.balance.isFinite ? min(1, max(-1, value.balance)) : 0
        return value
    }

    /// Conservative headroom: lowers the EQ preamp when a band is boosted.
    /// Multiple overlapping bands, reverb and input peaks can still clip:
    /// this reduces risk, it is not a true peak limiter.
    var effectivePreampDB: Float {
        guard enabled else { return 0 }
        let maximumBandBoost = bands.max() ?? 0
        let headroom = max(0, maximumBandBoost, bassDB, trebleDB)
        return min(preampDB, -headroom)
    }
}
