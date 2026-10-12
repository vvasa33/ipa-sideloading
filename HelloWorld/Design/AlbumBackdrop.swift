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
                ambient
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

    private var ambient: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.16, green: 0.18, blue: 0.62),
                    Color(red: 0.62, green: 0.22, blue: 0.48),
                    Color(red: 0.10, green: 0.42, blue: 0.58),
                ],
                startPoint: drift ? .topLeading : .bottomLeading,
                endPoint: drift ? .bottomTrailing : .topTrailing
            )
            Circle()
                .fill(Color(red: 1, green: 0.45, blue: 0.32).opacity(0.85))
                .frame(width: 460, height: 460)
                .blur(radius: 70)
                .offset(x: drift ? 180 : -40, y: drift ? -120 : 40)
            Circle()
                .fill(Color(red: 0.25, green: 0.85, blue: 0.78).opacity(0.75))
                .frame(width: 380, height: 380)
                .blur(radius: 60)
                .offset(x: drift ? -160 : 80, y: drift ? 140 : -20)
            Circle()
                .fill(Color(red: 0.98, green: 0.78, blue: 0.28).opacity(0.55))
                .frame(width: 280, height: 280)
                .blur(radius: 50)
                .offset(x: drift ? 40 : 200, y: drift ? 40 : 160)
        }
    }
}
