import SwiftUI

@main
struct HelloWorldApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model: model)
                .onOpenURL { url in
                    model.remote.handleCallback(url)
                }
        }
    }
}
