import SwiftUI

/// The screen only reacts to catalog, search and sort changes. Player time
/// updates (every 0.1 s) are observed by visible SongRowView items instead;
/// thousands of tracks are not re-sorted on every audio position tick.
struct SongListView: View {
    @ObservedObject var library: MusicLibrary
    let player: PlayerStore
    var songs: [MusicTrack]
    var title: String
    var onImport: (() -> Void)? = nil
    var onPlay: (() -> Void)? = nil

    @State private var search = ""
    @State private var pendingDelete: MusicTrack?
    @State private var orderedSongs: [MusicTrack] = []
    @AppStorage("localflac.songSort.key.v6") private var sortKeyRaw = SongSortKey.title.rawValue
    @AppStorage("localflac.songSort.ascending.v6") private var ascending = true

    private var sortKey: SongSortKey { SongSortKey(rawValue: sortKeyRaw) ?? .title }

    private var filtered: [MusicTrack] {
        let source = orderedSongs.isEmpty && !songs.isEmpty
            ? SongSortKey.ordered(songs, by: sortKey, ascending: ascending)
            : orderedSongs
        guard !search.isEmpty else { return source }
        return source.filter {
            $0.title.localizedCaseInsensitiveContains(search) ||
            $0.artist.localizedCaseInsensitiveContains(search) ||
            $0.album.localizedCaseInsensitiveContains(search)
        }
    }

    private func reorder() {
        orderedSongs = SongSortKey.ordered(songs, by: sortKey, ascending: ascending)
    }

    var body: some View {
        List {
            if songs.isEmpty {
                ContentUnavailableView("暂无本地音乐", systemImage: "music.note.list",
                                       description: Text("导入 .flac 歌曲后会显示在这里。"))
            }
            ForEach(filtered) { track in
                Button {
                    // Next/Previous follow the visible sorting and search results.
                    player.play(track, within: filtered)
                    onPlay?()
                } label: {
                    SongRowView(library: library, player: player, track: track)
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button("删除", role: .destructive) { pendingDelete = track }
                        .disabled(library.isWorking)
                }
                .contextMenu {
                    if !library.playlists.isEmpty {
                        Menu("添加到播放列表", systemImage: "text.badge.plus") {
                            ForEach(library.playlists) { playlist in
                                Button(playlist.name) { library.add(track: track, to: playlist.id) }
                            }
                        }
                    }
                }
            }
        }
        .onAppear(perform: reorder)
        .onChange(of: songs) { _, _ in reorder() }
        .onChange(of: sortKeyRaw) { _, _ in reorder() }
        .onChange(of: ascending) { _, _ in reorder() }
        .confirmationDialog("确定从 iPhone 删除这首歌曲？", isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        ), titleVisibility: .visible) {
            Button("删除 FLAC 及同目录同名 LRC", role: .destructive) {
                if let song = pendingDelete, !library.isWorking {
                    player.prepareForDeletion(trackID: song.id)
                    library.deleteSong(song)
                }
                pendingDelete = nil
            }
            Button("取消", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("此操作无法撤销。会移除歌曲文件及同目录同名歌词，并从播放列表删除引用；其他歌曲不受影响。")
        }
        .navigationTitle(title)
        .searchable(text: $search, prompt: "搜索歌曲、歌手、专辑")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("排序方式", selection: $sortKeyRaw) {
                        ForEach(SongSortKey.allCases, id: \.self) { item in
                            Text(item.label).tag(item.rawValue)
                        }
                    }
                    Divider()
                    Button {
                        ascending.toggle()
                    } label: {
                        Label(ascending ? "切换为降序" : "切换为升序",
                              systemImage: ascending ? "arrow.down" : "arrow.up")
                    }
                } label: {
                    Label("歌曲排序", systemImage: "arrow.up.arrow.down")
                }
                .accessibilityLabel("歌曲排序，当前：\(sortKey.label)，\(ascending ? "升序" : "降序")")
            }
            if let onImport {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onImport) {
                        Label("导入音乐", systemImage: "square.and.arrow.down")
                    }
                    .disabled(library.isWorking)
                }
            }
        }
    }
}

struct SongRowView: View {
    let library: MusicLibrary
    @ObservedObject var player: PlayerStore
    let track: MusicTrack

    private var isCurrent: Bool { player.current?.id == track.id }

    var body: some View {
        HStack(spacing: 12) {
            CoverView(library: library, track: track)
            VStack(alignment: .leading, spacing: 4) {
                Text(track.title)
                    .font(.body.weight(isCurrent ? .semibold : .medium))
                    .foregroundStyle(isCurrent ? Color.indigo : Color.primary)
                    .lineLimit(1)
                Text("\(track.artist) · \(track.album)")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Text(track.qualityLabel).font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
            if isCurrent {
                Image(systemName: player.isPlaying ? "waveform" : "pause.circle.fill")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(Color.indigo)
                    .accessibilityLabel(player.isPlaying ? "正在播放" : "当前歌曲已暂停")
            } else {
                Image(systemName: "play.circle")
                    .font(.title3).foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, isCurrent ? 5 : 0)
        .background(isCurrent ? Color.indigo.opacity(0.06) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(isCurrent ? (player.isPlaying ? "正在播放" : "暂停") : "")
    }
}
