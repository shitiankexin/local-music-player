import SwiftUI

struct LibraryManagerView: View {
    @ObservedObject var library: MusicLibrary
    @ObservedObject var player: PlayerStore
    var onImportFiles: () -> Void
    var onImportFolder: () -> Void
    @State private var pendingDelete: MusicTrack?

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button(action: onImportFiles) {
                        Label("导入 FLAC / LRC 文件", systemImage: "doc.badge.plus")
                    }
                    Button(action: onImportFolder) {
                        Label("导入整个文件夹（含子文件夹）", systemImage: "folder.badge.plus")
                    }
                    Text("文件夹导入保留层级；内容相同的 FLAC 只保存一份。iCloud 文件需要等待系统下载完成。")
                        .font(.caption).foregroundStyle(.secondary)
                } header: { Text("音乐导入") }
                .disabled(library.isWorking)

                if library.isWorking, let progress = library.progress {
                    Section("任务进度") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(progress.title).font(.headline)
                            Text(progress.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            if let fraction = progress.fraction {
                                ProgressView(value: fraction)
                                Text("\(Int(fraction * 100))%")
                                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            } else {
                                ProgressView()
                            }
                            Button("取消当前任务", role: .destructive) { library.cancelOperation() }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("音乐库维护") {
                    Button { library.refresh() } label: {
                        Label("增量扫描 / 同步 Finder 文件", systemImage: "arrow.clockwise")
                    }
                    Button { library.matchLyrics() } label: {
                        Label("批量匹配 LRC 歌词", systemImage: "text.alignleft")
                    }
                    Button { library.detectDuplicates() } label: {
                        Label("按 SHA-256 检测重复歌曲", systemImage: "doc.on.doc")
                    }
                    Text("同目录同名歌词优先；跨目录只对唯一的文件名或歌曲标题候选自动匹配，歧义歌词不覆盖。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .disabled(library.isWorking)

                Section("存储空间统计") {
                    HStack { Text("已索引歌曲"); Spacer(); Text("\(library.tracks.count) 首") }
                    HStack { Text("FLAC 音频"); Spacer(); Text(formatBytes(library.storage.audioBytes)) }
                    HStack { Text("LRC 歌词（\(library.storage.lyricFiles) 个）"); Spacer(); Text(formatBytes(library.storage.lyricBytes)) }
                    HStack { Text("封面文件（内嵌缓存与自定义）"); Spacer(); Text(formatBytes(library.storage.artworkBytes)) }
                    HStack {
                        Text("音乐相关占用").fontWeight(.semibold)
                        Spacer()
                        Text(formatBytes(library.storage.totalBytes)).fontWeight(.semibold)
                    }
                    HStack { Text("已关联歌词"); Spacer(); Text("\(library.storage.matchedTracks) 首") }
                    if library.storage.freeBytes > 0 {
                        HStack { Text("设备可用空间"); Spacer(); Text(formatBytes(library.storage.freeBytes)) }
                    }
                    Text("以上仅统计音乐 FLAC、LRC 和应用支持目录中的封面文件，不包含 App 在系统中的其他占用。")
                        .font(.caption).foregroundStyle(.secondary)
                }

                if let last = library.lastImport {
                    Section("最近一次导入") {
                        Text(last.display).font(.subheadline)
                        ForEach(last.errors, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                    }
                }
                if let last = library.lastScan {
                    Section("增量扫描结果") {
                        Text(last.display).font(.subheadline)
                        ForEach(last.messages, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                    }
                }
                if let last = library.lastLyricMatch {
                    Section("批量歌词匹配结果") {
                        Text(last.display).font(.subheadline)
                        if !last.examples.isEmpty {
                            Text("未处理示例：\(last.examples.joined(separator: "、"))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                Section("内容重复检测") {
                    if library.duplicateGroups.isEmpty {
                        Text("尚未发现重复组，或还未执行检测。")
                            .foregroundStyle(.secondary).font(.subheadline)
                    } else {
                        let redundant = library.duplicateGroups.reduce(Int64(0)) { $0 + $1.reclaimableBytes }
                        Text("\(library.duplicateGroups.count) 组 · 最多可回收约 \(formatBytes(redundant))")
                            .font(.subheadline.weight(.semibold))
                        Text("不会自动删除。请逐个确认需要保留的版本。")
                            .font(.caption).foregroundStyle(.secondary)
                        ForEach(library.duplicateGroups) { group in
                            DisclosureGroup("\(group.trackIDs.count) 份相同内容 · \(formatBytes(group.fileSize))") {
                                ForEach(group.trackIDs, id: \.self) { id in
                                    if let track = library.tracks.first(where: { $0.id == id }) {
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(track.title).font(.subheadline.weight(.medium))
                                            Text(track.relativePath).font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .textSelection(.enabled)
                                            Button("删除这一份", role: .destructive) { pendingDelete = track }
                                                .font(.caption).disabled(library.isWorking)
                                        }
                                        .padding(.vertical, 6)
                                    }
                                }
                            }
                        }
                    }
                }

                // Extra scrollable breathing room for floating iOS 26/27 tab bars.
                Section {
                    Color.clear
                        .frame(height: player.current == nil ? 14 : 100)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .accessibilityHidden(true)
                }
            }
            .navigationTitle("文件管理")
            .confirmationDialog("删除本地歌曲文件？", isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ), titleVisibility: .visible) {
                Button("永久删除 FLAC 及其同目录 LRC", role: .destructive) {
                    if let song = pendingDelete, !library.isWorking {
                        player.prepareForDeletion(trackID: song.id)
                        library.deleteSong(song)
                    }
                    pendingDelete = nil
                }
                Button("取消", role: .cancel) { pendingDelete = nil }
            } message: {
                Text("其他重复文件会保留；删除后曲库和播放列表将同步更新。无法撤销。")
            }
        }
    }
}
