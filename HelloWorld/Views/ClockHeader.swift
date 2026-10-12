import SwiftUI

struct ClockHeader: View {
    var date: Date
    var prominent: Bool
    var onLongPress: () -> Void

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 18) {
            Text(ClockFormat.time(from: date))
                .font(.system(size: prominent ? 168 : 104, weight: .medium, design: .default))
                .tracking(prominent ? -5 : -3.2)
                .monospacedDigit()
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.white, Color(red: 1, green: 0.96, blue: 0.90)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .shadow(color: Color.black.opacity(0.28), radius: 18, y: 8)
            Spacer(minLength: 12)
            Text(ClockFormat.day.string(from: date))
                .font(.system(size: prominent ? 32 : 22, weight: .semibold, design: .default))
                .tracking(0.3)
                .foregroundStyle(Color.white.opacity(0.92))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .shadow(color: Color.black.opacity(0.22), radius: 10, y: 4)
                .padding(.bottom, prominent ? 18 : 10)
        }
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 0.5) {
            onLongPress()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(ClockFormat.time(from: date)), \(ClockFormat.day.string(from: date))")
        .accessibilityHint("Opens settings")
    }
}

enum ClockFormat {
    static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter
    }()

    private static let time12: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "h:mm"
        return formatter
    }()

    private static let time24: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    static func time(from date: Date) -> String {
        let template = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current) ?? ""
        let uses12Hour = template.contains("a")
        return (uses12Hour ? time12 : time24).string(from: date)
    }
}
