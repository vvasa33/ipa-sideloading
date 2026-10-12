import SwiftUI
import UIKit

struct AlbumBackdrop: View {
    var image: UIImage?
    var token: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drift = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Theme.ink
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width * 1.25, height: geo.size.height * 1.25)
                        .scaleEffect(reduceMotion ? 1.08 : (drift ? 1.14 : 1.05))
                        .offset(
                            x: reduceMotion ? 0 : (drift ? 28 : -28),
                            y: reduceMotion ? 0 : (drift ? -18 : 18)
                        )
                        .saturation(0.82)
                        .id(token)
                        .transition(.opacity)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        .ignoresSafeArea()
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.9), value: token)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 40).repeatForever(autoreverses: true)) {
                drift = true
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
