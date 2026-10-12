import SwiftUI

struct ClockHeader: View {
    var date: Date
    var prominent: Bool
    var onLongPress: () -> Void

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 20) {
            Text(ClockFormat.time(from: date))
                .font(.system(size: prominent ? 112 : 64, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .shadow(color: Color.black.opacity(0.45), radius: 8, y: 2)
            Spacer(minLength: 16)
            Text(ClockFormat.day.string(from: date))
                .font(.system(size: prominent ? 34 : 26, weight: .regular, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.88))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .shadow(color: Color.black.opacity(0.45), radius: 8, y: 2)
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
