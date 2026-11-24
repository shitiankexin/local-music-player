import SwiftUI

@main
struct HongdaPlayerApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model.library)
                .environment(model.player)
        }
    }
}
