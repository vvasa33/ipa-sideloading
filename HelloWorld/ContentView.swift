import SwiftUI

struct ContentView: View {
    var body: some View {
        DashboardView()
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        PreviewHost()
            .previewInterfaceOrientation(.landscapeLeft)
            .previewLayout(.fixed(width: 1024, height: 768))
    }
}

private struct PreviewHost: View {
    @StateObject private var model = AppModel()

    var body: some View {
        ContentView()
            .environment(model: model)
    }
}
