import SwiftUI
import UIKit

struct DashboardView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var nowPlaying: NowPlayingStore
    @EnvironmentObject private var lyrics: LyricsStore
    @EnvironmentObject private var calendar: CalendarStore
    @EnvironmentObject private var stats: StatsStore
    @EnvironmentObject private var focus: FocusTimer
    @State private var showSettings = false

    var body: some View {
        ZStack {
            AlbumBackdrop(image: nowPlaying.backdrop, token: nowPlaying.backdropToken)
            LinearGradient(
                colors: [
                    Color.black.opacity(0.62),
                    Color.black.opacity(0.40),
                    Color.black.opacity(0.55),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            TimelineView(.periodic(from: .now, by: 1)) { context in
                layout(at: context.date)
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .sheet(isPresented: $showSettings) {
            SettingsSheet()
        }
        .task { await nowPlaying.run() }
        .task { await calendar.run() }
        .task { await stats.run() }
        .task { await focus.run() }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            lyrics.load(for: nowPlaying.track)
        }
        .onChange(of: nowPlaying.track?.id) { _ in
            lyrics.load(for: nowPlaying.track)
        }
        .onChange(of: scenePhase) { phase in
            guard phase == .active else { return }
            UIApplication.shared.isIdleTimerDisabled = true
            Task { await calendar.reload() }
        }
    }

    private func layout(at date: Date) -> some View {
        let collapsed = nowPlaying.isCollapsed(at: date)
        return VStack(spacing: 12) {
            ClockHeader(date: date, prominent: collapsed) {
                showSettings = true
            }
            .frame(
                maxWidth: .infinity,
                minHeight: collapsed ? 0 : 80,
                maxHeight: collapsed ? .infinity : 80,
                alignment: .leading
            )

            if !collapsed {
                NowPlayingView()
                    .frame(maxHeight: .infinity)
                    .transition(.opacity)
            }

            bottomRow
                .frame(height: 200)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .animation(reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.88), value: collapsed)
    }

    private var bottomRow: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 14
            let width = geo.size.width - spacing * 2
            HStack(spacing: spacing) {
                CalendarCell()
                    .frame(width: width * 5 / 12)
                StatsCell()
                    .frame(width: width * 4 / 12)
                FocusCell()
                    .frame(width: width * 3 / 12)
            }
        }
    }
}
