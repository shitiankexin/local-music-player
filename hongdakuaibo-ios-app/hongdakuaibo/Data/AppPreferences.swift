import Foundation

/// Typed UserDefaults / AppStorage keys for 洪达快播.
enum AppPreferences {
    enum Key {
        static let playbackMode = "hongdakuaibo.playbackMode.v4"
        static let audioEffects = "hongdakuaibo.audioEffects.v6"
        static let lastSession = "hongdakuaibo.lastSession.v5"
        static let lastQueue = "hongdakuaibo.lastQueue.v5"
        static let songSortKey = "hongdakuaibo.songSort.key.v6"
        static let songSortAscending = "hongdakuaibo.songSort.ascending.v6"

        static func lyricOffset(trackID: UUID) -> String {
            "lrc.offset.\(trackID.uuidString)"
        }
    }

    static var defaults: UserDefaults { .standard }

    static func lyricOffset(for trackID: UUID) -> TimeInterval {
        defaults.double(forKey: Key.lyricOffset(trackID: trackID))
    }

    static func setLyricOffset(_ offset: TimeInterval, for trackID: UUID) {
        defaults.set(offset, forKey: Key.lyricOffset(trackID: trackID))
    }

    static func removeLyricOffset(for trackID: UUID) {
        defaults.removeObject(forKey: Key.lyricOffset(trackID: trackID))
    }
}
