import SwiftUI

struct LyricsView: View {
    @Environment(PlayerStore.self) private var player

    private var selectedLine: Int? {
        player.lyrics.activeIndex(at: player.position, manualOffset: player.lyricOffset)
    }

    var body: some View {
        if player.lyrics.lines.isEmpty {
            ContentUnavailableView("没有找到 LRC 歌词", systemImage: "text.quote",
                                   description: Text("请导入与 FLAC 同名的 .lrc 文件。"))
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 26) {
                        ForEach(player.lyrics.lines) { line in
                            let highlighted = selectedLine == line.id
                            Text(line.text)
                                .font(highlighted ? .title3.weight(.bold) : .body.weight(.medium))
                                .foregroundStyle(highlighted ? Color.primary : Color.secondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal, 16)
                                .scaleEffect(highlighted ? 1.03 : 1.0)
                                .id(line.id)
                                .onTapGesture {
                                    let time = line.time + player.lyrics.embeddedOffset + player.lyricOffset
                                    player.seek(to: max(0, time))
                                }
                        }
                    }
                    .padding(.vertical, 120)
                }
                .onAppear {
                    if let selectedLine {
                        proxy.scrollTo(selectedLine, anchor: .center)
                    }
                }
                .onChange(of: selectedLine) { _, next in
                    guard let next else { return }
                    if player.isPlaying {
                        withAnimation(.easeOut(duration: 0.16)) {
                            proxy.scrollTo(next, anchor: .center)
                        }
                    } else {
                        // Don't leave the previous line on screen after headset pause.
                        proxy.scrollTo(next, anchor: .center)
                    }
                }
                .onChange(of: player.isPlaying) { _, playing in
                    if !playing, let selectedLine {
                        proxy.scrollTo(selectedLine, anchor: .center)
                    }
                }
            }
        }
    }
}
