import SwiftUI

struct PlaylistsView: View {
    @ObservedObject var library: MusicLibrary
    @ObservedObject var player: PlayerStore
    var onPlay: () -> Void = {}
    @State private var showingCreate = false
    @State private var playlistName = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(library.playlists) { playlist in
                    NavigationLink {
                        PlaylistDetailsView(library: library, player: player, playlistID: playlist.id, onPlay: onPlay)
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(playlist.name)
                                Text("\(playlist.trackIDs.count) 首")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: { Image(systemName: "music.note.list") }
                    }
                }
                .onDelete { offsets in
                    let ids = offsets.map { library.playlists[$0].id }
                    ids.forEach { library.deletePlaylist($0) }
                }
            }
            .overlay {
                if library.playlists.isEmpty {
                    ContentUnavailableView("还没有播放列表", systemImage: "text.badge.plus",
                                           description: Text("点击右上角 + 创建，再长按歌曲加入列表。"))
                }
            }
            .navigationTitle("播放列表")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingCreate = true } label: { Image(systemName: "plus") }
                }
            }
            .alert("新建播放列表", isPresented: $showingCreate) {
                TextField("例如：夜晚收藏", text: $playlistName)
                Button("创建") {
                    library.createPlaylist(name: playlistName)
                    playlistName = ""
                }
                Button("取消", role: .cancel) { playlistName = "" }
            } message: { Text("仅保存歌曲引用，不会复制音频文件。") }
        }
    }
}

struct PlaylistDetailsView: View {
    @ObservedObject var library: MusicLibrary
    @ObservedObject var player: PlayerStore
    let playlistID: UUID
    var onPlay: () -> Void = {}

    private var playlist: MusicPlaylist? { library.playlists.first { $0.id == playlistID } }
    private var songs: [MusicTrack] { playlist.map { library.tracks(in: $0) } ?? [] }

    var body: some View {
        List {
            ForEach(songs) { track in
                Button {
                    player.play(track, within: songs)
                    onPlay()
                } label: {
                    HStack(spacing: 12) {
                        CoverView(library: library, track: track)
                        VStack(alignment: .leading) {
                            Text(track.title).font(.body.weight(.medium))
                            Text(track.artist).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .swipeActions {
                    Button("移除", role: .destructive) {
                        library.remove(track: track, from: playlistID)
                    }
                }
            }
        }
        .navigationTitle(playlist?.name ?? "播放列表")
    }
}
