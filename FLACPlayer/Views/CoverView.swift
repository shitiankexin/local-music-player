import SwiftUI

struct CoverView: View {
    @ObservedObject var library: MusicLibrary
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
                    LinearGradient(colors: [Color.indigo.opacity(0.22),
                                            Color.blue.opacity(0.07),
                                            Color(uiColor: .secondarySystemBackground)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "waveform")
                        .font(.system(size: size * 0.33, weight: .medium))
                        .foregroundStyle(Color.indigo.opacity(0.65))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: max(8, size * 0.13)))
        .accessibilityLabel("专辑封面")
    }
}
