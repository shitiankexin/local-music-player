import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// Full-screen now-playing view. The lyrics page is LEFT of the cover page,
/// so a rightward swipe on the cover reveals lyrics naturally.
struct PlayerView: View {
    @Environment(MusicLibrary.self) private var library
    @Environment(PlayerStore.self) private var player
    @Environment(\.dismiss) private var dismiss

    private enum PlayerPage: Hashable {
        case lyrics
        case cover
    }

    @State private var page: PlayerPage = .cover
    @State private var scrubbing: Double?
    @State private var showPhotoPicker = false
    @State private var showEffects = false
    @State private var showCoverFileImporter = false
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var artworkTarget: MusicTrack?

    private func timeLabel(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite else { return "0:00" }
        let whole = max(0, Int(seconds))
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                header

                if let track = player.current {
                    // Native horizontal paging. From the COVER (page 2),
                    // swipe RIGHT to show LYRICS (page 1).
                    TabView(selection: $page) {
                        LyricsView()
                            .padding(.horizontal, 16)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .tag(PlayerPage.lyrics)

                        coverPage(track: track, availableSize: geometry.size)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .tag(PlayerPage.cover)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityHint("封面页面向右滑动查看歌词；歌词页面向左滑动返回封面")

                    pageSwitcher
                        .padding(.bottom, 14)

                    playbackControls(for: track)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 18)
                } else {
                    ContentUnavailableView("尚未播放歌曲", systemImage: "play.slash",
                                           description: Text("返回歌曲列表选择一首 FLAC。"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                LinearGradient(colors: [Color.accentColor.opacity(0.12),
                                        Color(uiColor: .systemBackground),
                                        Color(uiColor: .systemBackground)],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
            }
        }
        .tint(.accentColor)
        .sheet(isPresented: $showEffects) {
            NavigationStack {
                AudioEffectsView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("完成") { showEffects = false }
                        }
                    }
            }
        }
        .onChange(of: player.current?.id) { _, _ in scrubbing = nil }
        .photosPicker(isPresented: $showPhotoPicker, selection: $pickedPhoto, matching: .images)
        .onChange(of: pickedPhoto) { _, selection in
            guard let selection, let target = artworkTarget else { return }
            Task {
                defer { pickedPhoto = nil }
                do {
                    guard let data = try await selection.loadTransferable(type: Data.self) else {
                        library.lastError = "无法读取所选照片"
                        return
                    }
                    await library.setCustomArtwork(data, for: target)
                } catch {
                    library.lastError = "读取照片失败：\(error.localizedDescription)"
                }
            }
        }
        .fileImporter(isPresented: $showCoverFileImporter,
                      allowedContentTypes: [.image]) { result in
            guard let target = artworkTarget else { return }
            switch result {
            case .success(let file):
                Task {
                    let access = file.startAccessingSecurityScopedResource()
                    defer { if access { file.stopAccessingSecurityScopedResource() } }
                    do {
                        let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                        guard size <= 25 * 1024 * 1024 else {
                            library.lastError = "封面文件不能超过 25 MB"
                            return
                        }
                        await library.setCustomArtwork(try Data(contentsOf: file), for: target)
                    } catch { library.lastError = "读取封面文件失败：\(error.localizedDescription)" }
                }
            case .failure(let error):
                library.lastError = "选择封面失败：\(error.localizedDescription)"
            }
        }
    }

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.down")
                    .font(.title3.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("收起播放页")

            Spacer()
            Text("正在播放")
                .font(.subheadline.weight(.semibold))
            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    page = page == .cover ? .lyrics : .cover
                }
            } label: {
                Image(systemName: page == .cover ? "text.quote" : "square.stack")
                    .font(.headline)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(page == .cover ? "查看歌词" : "查看封面")
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }

    @ViewBuilder
    private func coverPage(track: MusicTrack, availableSize: CGSize) -> some View {
        let artworkSide = max(160, min(availableSize.width - 64, availableSize.height * 0.38, 350))
        VStack(spacing: 0) {
            Spacer(minLength: 8)
            CoverView(track: track, size: artworkSide)
                .shadow(color: .black.opacity(0.16), radius: 20, y: 10)
                .padding(.bottom, 24)

            VStack(spacing: 7) {
                Text(track.title)
                    .font(.title2.bold())
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                Text(track.artist)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(track.album)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                if library.artwork(for: track) == nil {
                    Text("暂无可用封面，可从下方添加")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Menu {
                    Button {
                        artworkTarget = track
                        showPhotoPicker = true
                    } label: {
                        Label("从照片中选择", systemImage: "photo")
                    }
                    Button {
                        artworkTarget = track
                        showCoverFileImporter = true
                    } label: {
                        Label("从文件中选择", systemImage: "folder")
                    }
                    if library.hasCustomArtwork(for: track) {
                        Button("恢复内嵌封面", systemImage: "arrow.uturn.backward") {
                            library.removeCustomArtwork(for: track)
                        }
                    }
                } label: {
                    Label("设置封面", systemImage: "photo.badge.plus")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.regularMaterial, in: Capsule())
                }
                .padding(.top, 12)
            }
            .padding(.horizontal, 20)
            Spacer(minLength: 8)
        }
    }

    private var pageSwitcher: some View {
        HStack(spacing: 18) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { page = .lyrics }
            } label: {
                Label("歌词", systemImage: "text.quote")
                    .foregroundStyle(page == .lyrics ? Color.accentColor : Color.secondary)
            }
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { page = .cover }
            } label: {
                Label("封面", systemImage: "square.stack")
                    .foregroundStyle(page == .cover ? Color.accentColor : Color.secondary)
            }
        }
        .buttonStyle(.plain)
        .font(.caption.weight(.medium))
        .accessibilityElement(children: .contain)
    }

    private func playbackControls(for track: MusicTrack) -> some View {
        VStack(spacing: 12) {
            Slider(value: Binding(
                get: { scrubbing ?? player.position },
                set: { scrubbing = $0 }),
                   in: 0...max(1, track.duration),
                   onEditingChanged: { editing in
                if !editing, let seconds = scrubbing {
                    player.seek(to: seconds)
                    scrubbing = nil
                }
            })
            .accessibilityLabel("播放进度")

            HStack {
                Text(timeLabel(scrubbing ?? player.position))
                Spacer()
                Text(timeLabel(track.duration))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)

            HStack(spacing: 46) {
                Button { player.previous() } label: {
                    Image(systemName: "backward.end.fill").font(.title2)
                        .frame(width: 40, height: 56)
                }
                .accessibilityLabel("上一首")

                Button { player.toggle() } label: {
                    Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 64))
                }
                .accessibilityLabel(player.isPlaying ? "暂停" : "播放")

                Button { player.next() } label: {
                    Image(systemName: "forward.end.fill").font(.title2)
                        .frame(width: 40, height: 56)
                }
                .accessibilityLabel("下一首")
            }
            .buttonStyle(.plain)
            .padding(.vertical, 1)

            HStack {
                Button { player.cyclePlaybackMode() } label: {
                    Label(player.playbackMode.title, systemImage: player.playbackMode.symbol)
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.accentColor.opacity(0.10), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("当前为\(player.playbackMode.title)，点击切换播放模式")
                Spacer()
                Button { showEffects = true } label: {
                    Label(player.audioEffects.enabled ? "音效已开" : "音效", systemImage: "slider.horizontal.3")
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.accentColor.opacity(player.audioEffects.enabled ? 0.17 : 0.08),
                                    in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("打开均衡器和音效设置")
            }

            HStack(spacing: 4) {
                Image(systemName: "waveform")
                Text("FLAC \(track.bitDepth)-bit · \(Double(track.sampleRate) / 1000, specifier: "%.1f") kHz")
                Spacer(minLength: 8)
                if player.actualOutputSampleRate > 0 {
                    Text("输出 \(Double(player.actualOutputSampleRate) / 1000, specifier: "%.1f") kHz")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if page == .lyrics && !player.lyrics.lines.isEmpty {
                HStack(spacing: 7) {
                    Text("歌词偏移")
                        .font(.caption2)
                        .fixedSize()
                    Slider(value: Binding(
                        get: { player.lyricOffset },
                        set: { player.setLyricOffset($0) }),
                           in: -5...5, step: 0.1)
                        .accessibilityLabel("歌词时间偏移")
                    Text("\(player.lyricOffset, specifier: "%+.1f")s")
                        .font(.caption2.monospacedDigit())
                        .frame(width: 40)
                    Button("重置") { player.setLyricOffset(0) }
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
            }
        }
    }
}


// MARK: - 10-band EQ / real-time audio effects
// Accessible from the now-playing sheet and from 管理 → 音效与均衡器.
struct AudioEffectsView: View {
    @Environment(PlayerStore.self) private var player

    private let frequencyLabels = ["31", "62", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]
    private var enabled: Bool { player.audioEffects.enabled }

    var body: some View {
        Form {
            Section {
                Toggle("启用音效", isOn: Binding(
                    get: { player.audioEffects.enabled },
                    set: { value in player.modifyAudioEffects { $0.enabled = value } }
                ))
                Label(enabled ? "正在使用自定义音效" : "原音模式（默认）",
                      systemImage: enabled ? "waveform" : "checkmark.shield")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text("关闭后旁路 EQ 和混响，不修改原始 FLAC 文件；系统音频输出仍可能重采样。")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("音效总开关") }

            Section {
                Picker("均衡器预设", selection: Binding(
                    get: { player.audioEffects.preset },
                    set: { player.chooseEQPreset($0) }
                )) {
                    ForEach(AudioEQPreset.allCases, id: \.self) { preset in
                        Text(preset.label).tag(preset)
                    }
                }
                ForEach(AudioEffectsSettings.frequencies.indices, id: \.self) { i in
                    HStack(spacing: 10) {
                        Text(frequencyLabels[i])
                            .font(.caption.monospacedDigit())
                            .frame(width: 35, alignment: .leading)
                        Slider(value: Binding(
                            get: { Double(player.audioEffects.bands[i]) },
                            set: { player.changeEQBand(at: i, gain: Float($0)) }
                        ), in: -12...12, step: 0.5)
                            .accessibilityLabel("\(frequencyLabels[i]) 赫兹")
                        Text("\(player.audioEffects.bands[i], specifier: "%+.1f")")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 45, alignment: .trailing)
                    }
                }
                Button("将十段 EQ 重置为平直") { player.chooseEQPreset(.flat) }
            } header: { Text("10 段均衡器 · dB") }
                footer: { Text("手动调整任一频段会切换为“自定义”预设；这里的数值只影响播放输出。") }
                .disabled(!enabled)

            Section("低音 / 高音") {
                adjustment("低音增强", value: player.audioEffects.bassDB, range: -12...12) { new in
                    player.modifyAudioEffects { $0.bassDB = new }
                }
                adjustment("高音增强", value: player.audioEffects.trebleDB, range: -12...12) { new in
                    player.modifyAudioEffects { $0.trebleDB = new }
                }
            }
            .disabled(!enabled)

            Section {
                adjustment("前级增益", value: player.audioEffects.preampDB, range: -12...0) { new in
                    player.modifyAudioEffects { $0.preampDB = new }
                }
                HStack {
                    Text("实际输出前级")
                    Spacer()
                    Text("\(player.audioEffects.effectivePreampDB, specifier: "%.1f") dB")
                        .monospacedDigit().foregroundStyle(.secondary)
                }
                Text("当任何频段提升时，自动降低前级增益以预留余量。它不能取代峰值限制器，仍需留意破音。")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("防削波余量") }
                .disabled(!enabled)

            Section("混响") {
                Toggle("启用混响", isOn: Binding(
                    get: { player.audioEffects.reverbEnabled },
                    set: { new in player.modifyAudioEffects { $0.reverbEnabled = new } }
                ))
                Picker("场景", selection: Binding(
                    get: { player.audioEffects.reverbSpace },
                    set: { new in player.modifyAudioEffects { $0.reverbSpace = new } }
                )) {
                    ForEach(AudioReverbSpace.allCases, id: \.self) { space in
                        Text(space.label).tag(space)
                    }
                }
                .disabled(!player.audioEffects.reverbEnabled)
                HStack {
                    Text("混响强度")
                    Slider(value: Binding(
                        get: { Double(player.audioEffects.reverbMix) },
                        set: { new in player.modifyAudioEffects { $0.reverbMix = Float(new) } }
                    ), in: 0...40, step: 1)
                    Text("\(Int(player.audioEffects.reverbMix))%")
                        .font(.caption.monospacedDigit()).frame(width: 44, alignment: .trailing)
                }
                .disabled(!player.audioEffects.reverbEnabled)
            }
            .disabled(!enabled)

            Section("左右声道") {
                HStack {
                    Text("左")
                    Slider(value: Binding(
                        get: { Double(player.audioEffects.balance) },
                        set: { new in player.modifyAudioEffects { $0.balance = Float(new) } }
                    ), in: -1...1, step: 0.1)
                    Text("右")
                }
                Button("恢复居中") { player.modifyAudioEffects { $0.balance = 0 } }
            }
            .disabled(!enabled)

            Section {
                Button("恢复原音默认设置") {
                    player.modifyAudioEffects { $0 = AudioEffectsSettings() }
                }
                Text("所有音效设置会保存在本机，下次打开 App 自动恢复；原音模式默认不开启任何 DSP 效果。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("音效与均衡器")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func adjustment(_ title: String, value: Float,
                            range: ClosedRange<Double>, onChange: @escaping (Float) -> Void) -> some View {
        HStack(spacing: 8) {
            Text(title).frame(width: 80, alignment: .leading)
            Slider(value: Binding(get: { Double(value) }, set: { onChange(Float($0)) }),
                   in: range, step: 0.5)
            Text("\(value, specifier: "%+.1f")")
                .font(.caption.monospacedDigit())
                .frame(width: 44, alignment: .trailing)
        }
    }
}
