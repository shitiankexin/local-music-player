import Foundation

/// Owns long-lived stores for the app lifetime (Observation + SwiftUI `@State`).
@MainActor
@Observable
final class AppModel {
    let library: MusicLibrary
    let player: PlayerStore

    init() {
        let library = MusicLibrary()
        self.library = library
        self.player = PlayerStore(library: library)
    }
}
