import SwiftUI

struct StatsCell: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var statsStore: StatsStore
    @EnvironmentObject private var nowPlaying: NowPlayingStore

    var body: some View {
        GlassPanel(tint: nowPlaying.palette.secondary) {
            VStack(alignment: .leading, spacing: 8) {
                Text(headline)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                bodyContent
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var headline: String {
        statsStore.stats?.hostname ?? "Ubuntu"
    }

    @ViewBuilder
    private var bodyContent: some View {
        if settings.ubuntuHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text("Add the Ubuntu address in Settings.")
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.82))
        } else if let stats = statsStore.stats {
            VStack(alignment: .leading, spacing: 8) {
                LazyVGrid(
                    columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                    spacing: 8
                ) {
                    metric("CPU", "\(Int(stats.cpuPercent.rounded()))%")
                    metric("RAM", "\(Int(stats.mem.percent.rounded()))%")
                    metric("Temp", stats.cpuTemp.map { "\(Int($0.rounded()))°" } ?? "n/a")
                    metric("Disk", "\(Int(stats.disk.percent.rounded()))%")
                    metric("Down", formatRate(stats.netRxBps))
                    metric("Up", formatRate(stats.netTxBps))
                }
                HStack {
                    Text("Uptime")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.68))
                    Spacer()
                    Text(formatUptime(stats.uptimeS))
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.white)
                }
                if statsStore.isOffline, let lastUpdate = statsStore.lastUpdate {
                    Text("Offline, last update \(stamp(lastUpdate))")
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.75))
                        .lineLimit(1)
                }
            }
        } else if statsStore.hasAttempted && statsStore.isOffline {
            Text("Ubuntu is not reachable")
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.82))
        } else {
            VStack(alignment: .leading, spacing: 10) {
                SkeletonBlock()
                SkeletonBlock().padding(.trailing, 40)
                Text("Waiting for Ubuntu")
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.75))
            }
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.68))
            Spacer(minLength: 4)
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private func formatRate(_ bytesPerSecond: Double) -> String {
        if bytesPerSecond < 1000 * 1024 {
            return String(format: "%.0f KB/s", bytesPerSecond / 1024)
        }
        return String(format: "%.1f MB/s", bytesPerSecond / 1024 / 1024)
    }

    private func formatUptime(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        let days = total / 86_400
        let hours = (total % 86_400) / 3600
        let minutes = (total % 3600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    private func stamp(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
