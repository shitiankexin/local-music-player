import SwiftUI

struct CoverView: View {
    @Environment(MusicLibrary.self) private var library
    let track: MusicTrack
    var size: CGFloat = 54

    var body: some View {
        Group {
            if let image = library.artwork(for: track) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    LinearGradient(
                        colors: [
                            Color.accentColor.opacity(0.22),
                            Color.accentColor.opacity(0.06),
                            Color(uiColor: .secondarySystemBackground)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Image(systemName: "waveform")
                        .font(.system(size: size * 0.33, weight: .medium))
                        .foregroundStyle(Color.accentColor.opacity(0.65))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: max(8, size * 0.13)))
        .accessibilityLabel("专辑封面")
        // Re-render when extracted/manual artwork changes.
        .id("\(track.id)-\(library.artworkRevision)")
    }
}
