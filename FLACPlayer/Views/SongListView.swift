import SwiftUI

struct SongListView: View {
    @ObservedObject var library: MusicLibrary
    @ObservedObject var player: PlayerStore
    var songs: [MusicTrack]
    var title: String
    var onImport: (() -> Void)? = nil
    var onPlay: (() -> Void)? = nil
    @State private var search = ""
    @State private var pendingDelete: MusicTrack?

    private var filtered: [MusicTrack] {
        guard !search.isEmpty else { return songs }
        return songs.filter {
            $0.title.localizedCaseInsensitiveContains(search) ||
            $0.artist.localizedCaseInsensitiveContains(search) ||
            $0.album.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        List {
            if songs.isEmpty {
                ContentUnavailableView("暂无本地音乐", systemImage: "music.note.list",
                                       description: Text("导入 .flac 歌曲后会显示在这里。"))
            }
            ForEach(filtered) { track in
                Button {
                    player.play(track, within: songs)
                    onPlay?()
                } label: {
                    HStack(spacing: 12) {
                        CoverView(library: library, track: track)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(track.title).font(.body.weight(.medium)).lineLimit(1)
                            Text("\(track.artist) · \(track.album)")
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            Text(track.qualityLabel).font(.caption2).foregroundStyle(.tertiary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "play.circle")
                            .font(.title3).foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
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
            if let onImport {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onImport) { Label("导入音乐", systemImage: "square.and.arrow.down") }
                        .disabled(library.isWorking)
                }
            }
        }
    }
}
