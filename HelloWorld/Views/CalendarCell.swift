import SwiftUI

struct CalendarCell: View {
    @EnvironmentObject private var calendar: CalendarStore
    @EnvironmentObject private var nowPlaying: NowPlayingStore

    var body: some View {
        GlassPanel(tint: nowPlaying.palette.primary) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Today")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white)
                content
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private var content: some View {
        if calendar.eventsAccess == .unknown && calendar.remindersAccess == .unknown {
            VStack(alignment: .leading, spacing: 10) {
                SkeletonBlock()
                SkeletonBlock().padding(.trailing, 36)
                SkeletonBlock().padding(.trailing, 72)
            }
        } else if calendar.events.isEmpty && calendar.reminders.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(emptyTitle)
                    .font(.system(size: 16, weight: .regular, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.86))
                if calendar.eventsAccess == .granted && calendar.remindersAccess == .denied {
                    Text("Reminders access is off")
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.7))
                }
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(calendar.events + calendar.reminders) { entry in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(entry.schedule)
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundStyle(Color.white.opacity(0.72))
                                .frame(width: 78, alignment: .leading)
                                .lineLimit(1)
                            Text(entry.title)
                                .font(.system(size: 16, weight: .regular, design: .rounded))
                                .foregroundStyle(Color.white)
                                .lineLimit(1)
                        }
                    }
                    if calendar.eventsAccess == .denied && calendar.remindersAccess == .granted {
                        Text("Calendar access is off")
                            .font(.system(size: 14, weight: .regular, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.7))
                            .padding(.top, 4)
                    }
                    if calendar.remindersAccess == .denied && calendar.eventsAccess == .granted {
                        Text("Reminders access is off")
                            .font(.system(size: 14, weight: .regular, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.7))
                            .padding(.top, 4)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private var emptyTitle: String {
        if calendar.eventsAccess == .denied && calendar.remindersAccess == .denied {
            return "Calendar and reminders access is off"
        }
        if calendar.eventsAccess == .denied && calendar.remindersAccess == .granted {
            return "Calendar access is off"
        }
        return "Nothing left today"
    }
}
