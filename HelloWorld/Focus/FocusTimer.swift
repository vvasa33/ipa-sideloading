import AudioToolbox
import Foundation
import UIKit

enum FocusPhase: String, Codable {
    case idle
    case focus
    case pausedFocus
    case rest
    case pausedRest
}

@MainActor
final class FocusTimer: ObservableObject {
    @Published private(set) var phase: FocusPhase = .idle
    @Published private(set) var focusMinutes = 25
    @Published private(set) var breakMinutes = 5
    @Published private(set) var pulseToken = 0

    private var endsAt: Date?
    private var pausedRemaining: TimeInterval = 0

    func run() async {
        restore()
        while !Task.isCancelled {
            tick()
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
    }

    func start(focusMinutes: Int, breakMinutes: Int) {
        self.focusMinutes = focusMinutes
        self.breakMinutes = breakMinutes
        phase = .focus
        pausedRemaining = TimeInterval(focusMinutes * 60)
        endsAt = Date().addingTimeInterval(pausedRemaining)
        save()
    }

    func pause(at date: Date = Date()) {
        switch phase {
        case .focus:
            pausedRemaining = remaining(at: date)
            phase = .pausedFocus
            endsAt = nil
        case .rest:
            pausedRemaining = remaining(at: date)
            phase = .pausedRest
            endsAt = nil
        default:
            return
        }
        save()
    }

    func resume() {
        switch phase {
        case .pausedFocus:
            phase = .focus
            endsAt = Date().addingTimeInterval(max(0, pausedRemaining))
        case .pausedRest:
            phase = .rest
            endsAt = Date().addingTimeInterval(max(0, pausedRemaining))
        default:
            return
        }
        save()
    }

    func stop() {
        phase = .idle
        endsAt = nil
        pausedRemaining = 0
        save()
    }

    func remaining(at date: Date) -> TimeInterval {
        switch phase {
        case .focus, .rest:
            return max(0, (endsAt ?? date).timeIntervalSince(date))
        case .pausedFocus, .pausedRest:
            return max(0, pausedRemaining)
        case .idle:
            return 0
        }
    }

    func fraction(at date: Date) -> Double {
        if phase == .idle { return 0 }
        let minutes: Int
        switch phase {
        case .rest, .pausedRest:
            minutes = breakMinutes
        default:
            minutes = focusMinutes
        }
        let total = TimeInterval(max(minutes, 1) * 60)
        return min(1, max(0, 1 - remaining(at: date) / total))
    }

    var phaseTitle: String {
        switch phase {
        case .pausedFocus, .pausedRest:
            return "Paused"
        case .rest:
            return "Break"
        case .idle, .focus:
            return "Focus"
        }
    }

    func clockString(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval.rounded(.up)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func tick(at date: Date = Date()) {
        guard let endsAt, date >= endsAt else { return }
        completePhase()
    }

    private func completePhase() {
        switch phase {
        case .focus:
            phase = .rest
            pausedRemaining = TimeInterval(breakMinutes * 60)
            endsAt = Date().addingTimeInterval(pausedRemaining)
            signal()
        case .rest:
            phase = .idle
            endsAt = nil
            pausedRemaining = 0
            signal()
        default:
            endsAt = nil
        }
        save()
    }

    private func signal() {
        pulseToken += 1
        AudioServicesPlaySystemSound(1057)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func restore() {
        guard
            let data = UserDefaults.standard.data(forKey: Keys.saved),
            let saved = try? JSONDecoder().decode(SavedFocus.self, from: data)
        else { return }
        focusMinutes = saved.focusMinutes
        breakMinutes = saved.breakMinutes
        pausedRemaining = saved.pausedRemaining
        switch saved.phase {
        case .focus, .rest:
            if let endsAt = saved.endsAt, endsAt > Date() {
                phase = saved.phase
                self.endsAt = endsAt
            } else {
                phase = .idle
                endsAt = nil
                UserDefaults.standard.removeObject(forKey: Keys.saved)
            }
        case .pausedFocus, .pausedRest:
            phase = saved.phase
            endsAt = nil
        case .idle:
            phase = .idle
        }
    }

    private func save() {
        let saved = SavedFocus(
            phase: phase,
            endsAt: endsAt,
            pausedRemaining: pausedRemaining,
            focusMinutes: focusMinutes,
            breakMinutes: breakMinutes
        )
        if let data = try? JSONEncoder().encode(saved) {
            UserDefaults.standard.set(data, forKey: Keys.saved)
        }
    }

    private struct SavedFocus: Codable {
        var phase: FocusPhase
        var endsAt: Date?
        var pausedRemaining: TimeInterval
        var focusMinutes: Int
        var breakMinutes: Int
    }

    private enum Keys {
        static let saved = "ipadcc.focus"
    }
}
