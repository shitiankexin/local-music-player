import SwiftUI

/// The Albums and Artists sections now live under one bottom tab: "资料库".
/// Keep the navigation stack here so changing sections does not add a new tab.
struct LibraryBrowserView: View {
    @ObservedObject var library: MusicLibrary
    @ObservedObject var player: PlayerStore
    var onPlay: () -> Void = {}
    @State private var selection: LibrarySection = .albums

    private enum LibrarySection: String, CaseIterable {
        case albums = "专辑"
        case artists = "歌手"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("浏览分类", selection: $selection) {
                    ForEach(LibrarySection.allCases, id: \.self) { section in
                        Text(section.rawValue).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 7)

                Group {
                    switch selection {
                    case .albums:
                        AlbumsView(library: library, player: player, onPlay: onPlay)
                    case .artists:
                        ArtistsView(library: library, player: player, onPlay: onPlay)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("资料库")
        }
    }
}

/// List content: does not create another NavigationStack.
struct AlbumsView: View {
    @ObservedObject var library: MusicLibrary
    @ObservedObject var player: PlayerStore
    var onPlay: () -> Void = {}

    private var groups: [String: [MusicTrack]] {
        Dictionary(grouping: library.tracks, by: { "\($0.albumArtist)\u{001F}\($0.album)" })
    }

    var body: some View {
        List(groups.keys.sorted(), id: \.self) { key in
            if let tracks = groups[key], let first = tracks.first {
                NavigationLink {
                    SongListView(library: library, player: player,
                                 songs: tracks, title: first.album, onPlay: onPlay)
                } label: {
                    HStack(spacing: 12) {
                        CoverView(library: library, track: first, size: 64)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(first.album).font(.headline)
                            Text("\(first.albumArtist) · \(tracks.count) 首")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .overlay {
            if groups.isEmpty {
                ContentUnavailableView("还没有专辑", systemImage: "square.stack",
                                       description: Text("导入 FLAC 后会按专辑标签自动归类。"))
            }
        }
    }
}

struct ArtistsView: View {
    @ObservedObject var library: MusicLibrary
    @ObservedObject var player: PlayerStore
    var onPlay: () -> Void = {}

    private var groups: [String: [MusicTrack]] {
        Dictionary(grouping: library.tracks, by: \.artist)
    }

    var body: some View {
        List(groups.keys.sorted(), id: \.self) { artist in
            if let tracks = groups[artist] {
                NavigationLink {
                    SongListView(library: library, player: player,
                                 songs: tracks, title: artist, onPlay: onPlay)
                } label: {
                    Label {
                        VStack(alignment: .leading) {
                            Text(artist).font(.headline)
                            Text("\(tracks.count) 首歌曲")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "person.crop.circle").font(.title2)
                    }
                }
            }
        }
        .overlay {
            if groups.isEmpty {
                ContentUnavailableView("还没有歌手", systemImage: "person.2",
                                       description: Text("导入 FLAC 后会按歌手标签自动归类。"))
            }
        }
    }
}
