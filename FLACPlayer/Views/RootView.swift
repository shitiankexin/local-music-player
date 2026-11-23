import SwiftUI
import UniformTypeIdentifiers

/// Four tabs. Use the native tab bar accessory on modern iOS and an inset
/// inside each tab on older iOS, keeping the tab bar visible while playing.
@MainActor
struct RootView: View {
    @StateObject private var library: MusicLibrary
    @StateObject private var player: PlayerStore
    @State private var showFileImporter = false
    @State private var showFolderImporter = false
    @State private var showPlayer = false
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let library = MusicLibrary()
        _library = StateObject(wrappedValue: library)
        _player = StateObject(wrappedValue: PlayerStore(library: library))
    }

    private var errorText: String? { player.errorMessage ?? library.lastError }
    private var showErrorBinding: Binding<Bool> {
        Binding(get: { errorText != nil }, set: { shown in
            if !shown { player.errorMessage = nil; library.lastError = nil }
        })
    }

    /// Use the native bottom accessory on iOS 26.1+ (including iOS 27), which
    /// knows how to avoid the floating system tab bar. On iOS 17–25, insert
    /// the bar into EACH tab content's safe area as a compatibility fallback.
    @ViewBuilder
    private func tabContent<Content: View>(_ content: Content, legacyInset: Bool) -> some View {
        if legacyInset {
            content.safeAreaInset(edge: .bottom, spacing: 0) {
                if player.current != nil {
                    MiniPlayerBar(library: library, player: player) {
                        showPlayer = true
                    }
                }
            }
        } else {
            content
        }
    }

    private func tabs(legacyInset: Bool) -> some View {
        TabView {
            tabContent(
                NavigationStack {
                    SongListView(library: library,
                                 player: player,
                                 songs: library.tracks,
                                 title: "本地音乐",
                                 onImport: { showFileImporter = true },
                                 onPlay: { showPlayer = true })
                }, legacyInset: legacyInset
            )
            .tabItem { Label("歌曲", systemImage: "music.note") }

            tabContent(
                LibraryBrowserView(library: library,
                                   player: player,
                                   onPlay: { showPlayer = true }),
                legacyInset: legacyInset
            )
            .tabItem { Label("资料库", systemImage: "square.stack.3d.up") }

            tabContent(
                PlaylistsView(library: library,
                              player: player,
                              onPlay: { showPlayer = true }),
                legacyInset: legacyInset
            )
            .tabItem { Label("列表", systemImage: "music.note.list") }

            tabContent(
                LibraryManagerView(library: library,
                                   player: player,
                                   onImportFiles: { showFileImporter = true },
                                   onImportFolder: { showFolderImporter = true }),
                legacyInset: legacyInset
            )
            .tabItem { Label("管理", systemImage: "folder") }
        }
    }

    var body: some View {
        Group {
            if #available(iOS 26.1, *) {
                tabs(legacyInset: false)
                    .tabBarMinimizeBehavior(.never)
                    .tabViewBottomAccessory(isEnabled: player.current != nil) {
                        MiniPlayerBar(library: library, player: player) {
                            showPlayer = true
                        }
                    }
            } else {
                tabs(legacyInset: true)
            }
        }
        .tint(.indigo)
        // Hide the tab bar and mini player completely while the player is open.
        .fullScreenCover(isPresented: $showPlayer) {
            PlayerView(library: library, player: player)
        }
        .fileImporter(isPresented: $showFileImporter,
                      allowedContentTypes: [UTType(filenameExtension: "flac") ?? .audio,
                                            UTType(filenameExtension: "lrc") ?? .plainText],
                      allowsMultipleSelection: true) { result in
            Task { @MainActor in
                switch result {
                case .success(let urls): library.importFiles(urls)
                case .failure(let error): library.lastError = "文件导入失败：\(error.localizedDescription)"
                }
            }
        }
        .fileImporter(isPresented: $showFolderImporter,
                      allowedContentTypes: [.folder],
                      allowsMultipleSelection: true) { result in
            Task { @MainActor in
                switch result {
                case .success(let folders): library.importFolders(folders)
                case .failure(let error): library.lastError = "文件夹导入失败：\(error.localizedDescription)"
                }
            }
        }
        .onOpenURL { library.importFiles([$0]) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { library.refresh() }
            if phase == .inactive || phase == .background { player.checkpointPlayback() }
        }
        .onChange(of: library.tracks.map(\.id)) { _, _ in player.reconcileLibrary() }
        .onChange(of: library.artworkRevision) { _, _ in player.refreshNowPlayingArtwork() }
        .alert("提示", isPresented: showErrorBinding) {
            Button("确定", role: .cancel) { }
        } message: { Text(errorText ?? "未知错误") }
    }
}

/// Compact controls above (not on top of) the system tab bar.
private struct MiniPlayerBar: View {
    @ObservedObject var library: MusicLibrary
    @ObservedObject var player: PlayerStore
    let onOpen: () -> Void

    var body: some View {
        if let track = player.current {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Button(action: onOpen) {
                        HStack(spacing: 10) {
                            CoverView(library: library, track: track, size: 43)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(track.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text(track.artist)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("打开正在播放：\(track.title)")

                    Button { player.toggle() } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title3)
                            .frame(width: 36, height: 44)
                    }
                    .accessibilityLabel(player.isPlaying ? "暂停" : "播放")

                    Button { player.next() } label: {
                        Image(systemName: "forward.end.fill")
                            .font(.headline)
                            .frame(width: 32, height: 44)
                    }
                    .accessibilityLabel("下一首")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 5)

                GeometryReader { geometry in
                    let fraction = track.duration > 0
                        ? min(1, max(0, player.position / track.duration))
                        : 0
                    ZStack(alignment: .leading) {
                        Color.primary.opacity(0.08)
                        Color.indigo.frame(width: geometry.size.width * CGFloat(fraction))
                    }
                }
                .frame(height: 2)
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 15))
            .clipShape(RoundedRectangle(cornerRadius: 15))
            .overlay {
                RoundedRectangle(cornerRadius: 15)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
            }
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .padding(.bottom, 5)
        }
    }
}
