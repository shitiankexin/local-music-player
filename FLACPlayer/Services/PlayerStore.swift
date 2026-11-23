import Foundation
import MediaPlayer
import AVFAudio
import UIKit

/// The four playback policies.  Persist raw values rather than enum ordinals
/// so changing the display order will not change a user's saved preference.
enum PlaybackMode: String, CaseIterable, Codable {
    case sequential
    case repeatAll
    case repeatOne
    case shuffle

    var title: String {
        switch self {
        case .sequential: return "顺序播放"
        case .repeatAll: return "列表循环"
        case .repeatOne: return "单曲循环"
        case .shuffle: return "随机播放"
        }
    }

    var symbol: String {
        switch self {
        case .sequential: return "arrow.right"
        case .repeatAll: return "repeat"
        case .repeatOne: return "repeat.1"
        case .shuffle: return "shuffle"
        }
    }

    var next: PlaybackMode {
        let all = Self.allCases
        let index = all.firstIndex(of: self) ?? 0
        return all[(index + 1) % all.count]
    }
}

/// Pure queue-navigation logic, shared by on-screen controls and system remote commands.
/// Random mode uses a shuffled bag and a back/forward history: it avoids repeats until
/// the bag has been exhausted, and Previous goes to the actual previously played song.
struct PlaybackQueueOrder {
    private(set) var mode: PlaybackMode
    private(set) var selected: UUID?
    private(set) var ids: [UUID] = []

    private var randomHistory: [UUID] = []
    private var randomCursor = 0
    private var randomPending: [UUID] = []

    init(mode: PlaybackMode = .sequential) {
        self.mode = mode
    }

    mutating func reset(ids: [UUID], selected: UUID) {
        self.ids = ids
        self.selected = ids.contains(selected) ? selected : ids.first
        resetRandomBag()
    }

    mutating func changeMode(_ newMode: PlaybackMode) {
        mode = newMode
        resetRandomBag()
    }

    /// Reconcile after a Finder import or deletion; preserve history for surviving songs.
    mutating func reconcile(ids newIDs: [UUID], selected wanted: UUID?) {
        ids = newIDs
        guard !newIDs.isEmpty else {
            selected = nil
            randomHistory.removeAll()
            randomPending.removeAll()
            randomCursor = 0
            return
        }

        let previous = selected
        let candidate = wanted ?? previous
        selected = candidate.flatMap { newIDs.contains($0) ? $0 : nil } ?? newIDs[0]

        guard mode == .shuffle, let selected else { return }
        if randomHistory.contains(selected) {
            randomHistory.removeAll { !newIDs.contains($0) }
            randomCursor = randomHistory.firstIndex(of: selected) ?? 0
            randomPending.removeAll { !newIDs.contains($0) }
            let known = Set(randomHistory).union(randomPending)
            randomPending.append(contentsOf: newIDs.filter { !known.contains($0) }.shuffled())
        } else {
            resetRandomBag()
        }
    }

    /// Returns nil when sequential mode reaches the end of the list.
    mutating func advance(automatically: Bool) -> UUID? {
        guard let selected, !ids.isEmpty else { return nil }
        if automatically && mode == .repeatOne { return selected }

        if mode == .shuffle {
            if randomCursor + 1 < randomHistory.count {
                randomCursor += 1
                self.selected = randomHistory[randomCursor]
                return self.selected
            }
            if randomPending.isEmpty {
                randomPending = ids.filter { $0 != selected }.shuffled()
            }
            guard let next = randomPending.popLast() else {
                // There is only one song in the queue.
                return selected
            }
            randomHistory.append(next)
            randomCursor = randomHistory.count - 1
            self.selected = next
            return next
        }

        guard let position = ids.firstIndex(of: selected) else { return nil }
        if position + 1 < ids.count {
            self.selected = ids[position + 1]
            return self.selected
        }
        switch mode {
        case .sequential:
            return nil
        case .repeatAll, .repeatOne:
            self.selected = ids[0]
            return self.selected
        case .shuffle:
            return nil // handled above
        }
    }

    /// Returns nil at the beginning of a sequential list or random history.
    mutating func retreat() -> UUID? {
        guard let selected, !ids.isEmpty else { return nil }
        if mode == .shuffle {
            guard randomCursor > 0 else { return nil }
            randomCursor -= 1
            self.selected = randomHistory[randomCursor]
            return self.selected
        }
        guard let position = ids.firstIndex(of: selected) else { return nil }
        if position > 0 {
            self.selected = ids[position - 1]
            return self.selected
        }
        switch mode {
        case .repeatAll, .repeatOne:
            self.selected = ids[ids.count - 1]
            return self.selected
        case .sequential, .shuffle:
            return nil
        }
    }

    private mutating func resetRandomBag() {
        randomHistory = selected.map { [$0] } ?? []
        randomCursor = 0
        randomPending = ids.filter { $0 != selected }.shuffled()
    }
}

/// A tiny, versionable UI bookmark. The audio bytes and lyrics stay on disk.
/// Keeping the relative path allows recovery if the catalog is re-indexed.
struct PlaybackSession: Codable, Equatable {
    let trackID: UUID
    let relativePath: String
    let seconds: TimeInterval

    func clamped(to duration: TimeInterval) -> TimeInterval {
        guard seconds.isFinite else { return 0 }
        return min(max(0, seconds), max(0, duration))
    }
}

@MainActor
final class PlayerStore: ObservableObject {
    @Published private(set) var current: MusicTrack?
    @Published private(set) var isPlaying = false
    @Published private(set) var position: TimeInterval = 0
    @Published private(set) var lyrics = LRCFile(lines: [], embeddedOffset: 0)
    @Published private(set) var lyricOffset: TimeInterval = 0
    @Published private(set) var actualOutputSampleRate: Double = 0
    @Published private(set) var playbackMode: PlaybackMode
    @Published private(set) var audioEffects: AudioEffectsSettings
    @Published var errorMessage: String?

    private let library: MusicLibrary
    private let audio = FLACAudioEngine()
    private var playbackQueue: [MusicTrack] = []
    private var order: PlaybackQueueOrder
    private var timer: Timer?
    private var artworkTrackID: UUID?
    private var nowPlayingArtwork: MPMediaItemArtwork?
    private static let modeKey = "localflac.playbackMode.v4"
    private static let effectsKey = "localflac.audioEffects.v6"
    private static let sessionKey = "localflac.lastSession.v5"
    private static let queueKey = "localflac.lastQueue.v5"
    private var needsAudioPreparation = false
    private var timelineRevision: UInt64 = 0
    private var lastCheckpoint = Date.distantPast

    init(library: MusicLibrary) {
        self.library = library
        let saved = UserDefaults.standard.string(forKey: Self.modeKey)
        let mode = saved.flatMap(PlaybackMode.init(rawValue:)) ?? .sequential
        self.playbackMode = mode
        self.order = PlaybackQueueOrder(mode: mode)
        let effectsData = UserDefaults.standard.data(forKey: Self.effectsKey)
        let restoredEffects = effectsData.flatMap {
            try? JSONDecoder().decode(AudioEffectsSettings.self, from: $0)
        }
        self.audioEffects = (restoredEffects ?? AudioEffectsSettings()).sanitized()
        audio.updateEffects(audioEffects)

        audio.onFinished = { [weak self] in self?.advance(automatically: true) }
        audio.onFailure = { [weak self] message in
            guard let self else { return }
            self.timelineRevision &+= 1
            self.isPlaying = false
            self.needsAudioPreparation = true
            self.errorMessage = message
            self.saveSession()
            self.updateNowPlaying()
        }
        audio.onPlaybackInterrupted = { [weak self] seconds in
            guard let self, let song = self.current else { return }
            self.timelineRevision &+= 1
            self.isPlaying = false
            self.position = self.clamped(seconds, for: song)
            self.saveSession()
            self.updateNowPlaying()
        }
        audio.onPlaybackResumed = { [weak self] in
            guard let self else { return }
            self.timelineRevision &+= 1
            self.isPlaying = true
            self.saveSession()
            self.updateNowPlaying()
        }
        audio.onOutputSampleRate = { [weak self] rate in
            self?.actualOutputSampleRate = rate
            // The audio session is now active; advertise playback to the lock screen.
            self?.updateNowPlaying()
        }
        configureRemoteCommands()
        restoreLastSession()
        // Faster UI refresh avoids a previous-line lyric highlight when pausing.
        let t = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func play(_ track: MusicTrack, within tracks: [MusicTrack]? = nil) {
        let list = tracks ?? library.tracks
        playbackQueue = list.contains(where: { $0.id == track.id }) ? list : list + [track]
        order.reset(ids: playbackQueue.map(\.id), selected: track.id)
        saveQueue() // queue changes rarely; don't rewrite thousands of UUIDs each tick
        startCurrent(trackID: track.id)
    }

    private func clamped(_ seconds: TimeInterval, for song: MusicTrack) -> TimeInterval {
        guard seconds.isFinite else { return 0 }
        return song.duration > 0 ? min(max(0, seconds), song.duration) : max(0, seconds)
    }

    private func loadLyrics(for track: MusicTrack) {
        lyricOffset = UserDefaults.standard.double(forKey: "lrc.offset.\(track.id)")
        if let url = library.lyricsURL(for: track) {
            lyrics = LRCFile.load(from: url) ?? LRCFile(lines: [], embeddedOffset: 0)
        } else {
            lyrics = LRCFile(lines: [], embeddedOffset: 0)
        }
    }

    /// Show the last song and seek point, but NEVER auto-play on launch.
    private func restoreLastSession() {
        guard current == nil,
              let data = UserDefaults.standard.data(forKey: Self.sessionKey),
              let saved = try? JSONDecoder().decode(PlaybackSession.self, from: data),
              let track = library.tracks.first(where: {
                  $0.id == saved.trackID || $0.relativePath == saved.relativePath
              }), FileManager.default.fileExists(atPath: library.fileURL(for: track).path)
        else { return }

        let lookup = Dictionary(uniqueKeysWithValues: library.tracks.map { ($0.id, $0) })
        let ids = UserDefaults.standard.data(forKey: Self.queueKey).flatMap {
            try? JSONDecoder().decode([UUID].self, from: $0)
        } ?? []
        playbackQueue = ids.isEmpty ? library.tracks : ids.compactMap { lookup[$0] }
        if !playbackQueue.contains(where: { $0.id == track.id }) {
            playbackQueue.append(track)
        }
        if playbackQueue.isEmpty { playbackQueue = library.tracks }
        order.reset(ids: playbackQueue.map(\.id), selected: track.id)
        current = track
        position = saved.clamped(to: track.duration)
        isPlaying = false
        needsAudioPreparation = true
        loadLyrics(for: track)
        updateNowPlaying()
    }

    private func saveSession() {
        guard let song = current else {
            UserDefaults.standard.removeObject(forKey: Self.sessionKey)
            return
        }
        let bookmark = PlaybackSession(trackID: song.id, relativePath: song.relativePath,
                                       seconds: clamped(position, for: song))
        if let data = try? JSONEncoder().encode(bookmark) {
            UserDefaults.standard.set(data, forKey: Self.sessionKey)
        }
        lastCheckpoint = Date()
    }

    private func saveQueue() {
        if let data = try? JSONEncoder().encode(playbackQueue.map(\.id)) {
            UserDefaults.standard.set(data, forKey: Self.queueKey)
        }
    }

    /// Called when app enters background; keep music playing while saving the bookmark.
    func checkpointPlayback() {
        guard let expectedID = current?.id else { return }
        let revision = timelineRevision
        if isPlaying && !needsAudioPreparation {
            audio.currentPosition { [weak self] seconds in
                guard let self, self.isPlaying, self.timelineRevision == revision,
                      let song = self.current, song.id == expectedID else { return }
                self.position = self.clamped(seconds, for: song)
                self.saveSession()
            }
        } else {
            saveSession()
        }
    }

    func refreshNowPlayingArtwork() {
        artworkTrackID = nil
        nowPlayingArtwork = nil
        updateNowPlaying()
    }

    // MARK: - Equalizer / effect preferences (saved independently of playback)
    func modifyAudioEffects(_ update: (inout AudioEffectsSettings) -> Void) {
        var value = audioEffects
        update(&value)
        value = value.sanitized()
        audioEffects = value
        if let bytes = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(bytes, forKey: Self.effectsKey)
        }
        audio.updateEffects(value)
    }

    func chooseEQPreset(_ preset: AudioEQPreset) {
        modifyAudioEffects {
            $0.preset = preset
            if preset != .custom { $0.bands = preset.gains }
        }
    }

    func changeEQBand(at index: Int, gain: Float) {
        guard AudioEffectsSettings.frequencies.indices.contains(index) else { return }
        modifyAudioEffects {
            $0.bands[index] = gain
            $0.preset = .custom
        }
    }

    func cyclePlaybackMode() {
        setPlaybackMode(playbackMode.next)
    }

    func setPlaybackMode(_ mode: PlaybackMode) {
        playbackMode = mode
        order.changeMode(mode)
        UserDefaults.standard.set(mode.rawValue, forKey: Self.modeKey)
        updateNowPlaying()
    }

    private func startCurrent(trackID: UUID) {
        guard let track = playbackQueue.first(where: { $0.id == trackID }) else { return }
        timelineRevision &+= 1
        current = track
        position = 0
        actualOutputSampleRate = 0
        needsAudioPreparation = false
        isPlaying = true
        errorMessage = nil
        loadLyrics(for: track)
        audio.open(url: library.fileURL(for: track))
        saveSession()
        updateNowPlaying()
    }

    /// Stop the decoder before deleting its file and remove stale queue references.
    func prepareForDeletion(trackID: UUID) {
        if current?.id == trackID {
            timelineRevision &+= 1
            audio.stop()
            current = nil
            position = 0
            isPlaying = false
            lyrics = LRCFile(lines: [], embeddedOffset: 0)
            actualOutputSampleRate = 0
            artworkTrackID = nil
            nowPlayingArtwork = nil
            needsAudioPreparation = false
            saveSession() // removes the deleted song's bookmark
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        }
        playbackQueue.removeAll { $0.id == trackID }
        saveQueue()
        order.reconcile(ids: playbackQueue.map(\.id), selected: current?.id)
        updateNowPlaying()
    }

    func reconcileLibrary() {
        let available = Dictionary(uniqueKeysWithValues: library.tracks.map { ($0.id, $0) })
        if let song = current, available[song.id] == nil {
            prepareForDeletion(trackID: song.id)
        }
        playbackQueue = playbackQueue.compactMap { available[$0.id] }
        if current != nil { saveQueue() }
        if let song = current, let replacement = available[song.id] {
            current = replacement
        }
        order.reconcile(ids: playbackQueue.map(\.id), selected: current?.id)
        if current == nil { restoreLastSession() }
        updateRemoteAvailability()
    }

    func toggle() { isPlaying ? pause() : resume() }

    func pause() {
        guard let song = current else { return }
        timelineRevision &+= 1
        let revision = timelineRevision
        isPlaying = false
        saveSession() // immediate fallback until the audio queue replies
        updateNowPlaying()
        if needsAudioPreparation { return }
        audio.pause { [weak self] seconds in
            guard let self, let actual = self.current, actual.id == song.id,
                  self.timelineRevision == revision, !self.isPlaying else { return }
            // Snap progress/lyrics/lock screen to the SAME paused sample.
            self.position = self.clamped(seconds, for: actual)
            self.saveSession()
            self.updateNowPlaying()
        }
    }

    func resume() {
        guard let track = current else { return }
        timelineRevision &+= 1
        // A finished player node has no buffers left. Rewind before resuming.
        if track.duration > 0 && position >= track.duration - 0.15 {
            position = 0
            if !needsAudioPreparation { audio.seek(seconds: 0) }
        }
        if needsAudioPreparation {
            // Restored sessions are intentionally loaded lazily (no startup audio).
            audio.open(url: library.fileURL(for: track), playAutomatically: false)
            audio.seek(seconds: position)
            needsAudioPreparation = false
        }
        audio.resume()
        isPlaying = true
        saveSession()
        updateNowPlaying()
    }

    func seek(to seconds: TimeInterval) {
        guard let track = current else { return }
        timelineRevision &+= 1
        let clipped = clamped(seconds, for: track)
        position = clipped
        if !needsAudioPreparation { audio.seek(seconds: clipped) }
        saveSession()
        updateNowPlaying()
    }

    func next() { advance(automatically: false) }

    private func advance(automatically: Bool) {
        guard !playbackQueue.isEmpty else { return }
        if let nextID = order.advance(automatically: automatically) {
            startCurrent(trackID: nextID)
        } else if automatically {
            timelineRevision &+= 1
            isPlaying = false
            position = current?.duration ?? position
            saveSession()
            updateNowPlaying()
        }
    }

    func previous() {
        // Headset triple-press means "previous TRACK" even if the current song
        // has been playing for more than a few seconds.
        guard !playbackQueue.isEmpty else { return }
        if let previousID = order.retreat() {
            startCurrent(trackID: previousID)
        } else {
            seek(to: 0)
        }
    }

    func setLyricOffset(_ offset: TimeInterval) {
        lyricOffset = offset
        if let track = current {
            UserDefaults.standard.set(offset, forKey: "lrc.offset.\(track.id)")
        }
    }

    private func tick() {
        // Paused bookmarks are immutable until a new seek or explicit resume.
        guard isPlaying, !needsAudioPreparation, let expectedID = current?.id else { return }
        let revision = timelineRevision
        audio.currentPosition { [weak self] seconds in
            guard let self, self.isPlaying, self.timelineRevision == revision,
                  let song = self.current, song.id == expectedID else { return }
            self.position = self.clamped(seconds, for: song)
            if Date().timeIntervalSince(self.lastCheckpoint) >= 3 {
                self.saveSession()
            }
            // iOS advances the Now Playing clock itself; no metadata update every tick.
        }
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async { self?.resume() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async { self?.pause() }
            return .success
        }
        // Many earphones send TOGGLE, rather than distinct PLAY or PAUSE.
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async { self?.toggle() }
            return .success
        }
        // The iOS system maps headset gestures (e.g. double/triple press)
        // onto these semantic commands; no raw button-count detection is needed.
        center.nextTrackCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async { self?.next() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async { self?.previous() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let seek = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            DispatchQueue.main.async { self?.seek(to: seek.positionTime) }
            return .success
        }
        updateRemoteAvailability()
    }

    private func updateRemoteAvailability() {
        let center = MPRemoteCommandCenter.shared()
        let enabled = current != nil
        center.playCommand.isEnabled = enabled
        center.pauseCommand.isEnabled = enabled
        center.togglePlayPauseCommand.isEnabled = enabled
        center.nextTrackCommand.isEnabled = enabled && playbackQueue.count > 1
        center.previousTrackCommand.isEnabled = enabled && playbackQueue.count > 1
        center.changePlaybackPositionCommand.isEnabled = enabled
    }

    private func updateNowPlaying() {
        updateRemoteAvailability()
        guard let song = current else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            artworkTrackID = nil
            nowPlayingArtwork = nil
            return
        }
        if artworkTrackID != song.id {
            artworkTrackID = song.id
            if let cover = library.artwork(for: song) {
                nowPlayingArtwork = MPMediaItemArtwork(boundsSize: cover.size) { _ in cover }
            } else {
                nowPlayingArtwork = nil
            }
        }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: song.title,
            MPMediaItemPropertyArtist: song.artist,
            MPMediaItemPropertyAlbumTitle: song.album,
            MPMediaItemPropertyPlaybackDuration: song.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        if let artwork = nowPlayingArtwork {
            info[MPMediaItemPropertyArtwork] = artwork
        }
        if let queuePosition = playbackQueue.firstIndex(where: { $0.id == song.id }) {
            info[MPNowPlayingInfoPropertyPlaybackQueueIndex] = queuePosition
            info[MPNowPlayingInfoPropertyPlaybackQueueCount] = playbackQueue.count
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
