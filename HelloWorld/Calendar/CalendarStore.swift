import EventKit
import SwiftUI

struct AgendaEntry: Identifiable, Equatable {
    var id: String
    var title: String
    var schedule: String
    var kind: Kind

    enum Kind: Equatable {
        case event
        case reminder
    }
}

@MainActor
final class CalendarStore: ObservableObject {
    enum Access: Equatable {
        case unknown
        case granted
        case denied
    }

    @Published var eventsAccess: Access = .unknown
    @Published var remindersAccess: Access = .unknown
    @Published var events: [AgendaEntry] = []
    @Published var reminders: [AgendaEntry] = []

    private let store = EKEventStore()
    private var observing = false

    func run() async {
        guard !Runtime.isPreview else {
            eventsAccess = .granted
            remindersAccess = .granted
            events = [
                AgendaEntry(id: "preview-event", title: "Studio time", schedule: "3:00 PM", kind: .event),
            ]
            reminders = [
                AgendaEntry(id: "preview-reminder", title: "Mail the contract", schedule: "5:30 PM", kind: .reminder),
            ]
            return
        }
        observe()
        await reload()
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            await reload()
        }
    }

    func reload() async {
        let eventsAllowed = await resolve(.event)
        let remindersAllowed = await resolve(.reminder)
        eventsAccess = eventsAllowed ? .granted : .denied
        remindersAccess = remindersAllowed ? .granted : .denied
        let now = Date()
        if eventsAllowed {
            events = loadEvents(now: now)
        } else {
            events = []
        }
        if remindersAllowed {
            reminders = await loadReminders(now: now)
        } else {
            reminders = []
        }
    }

    private func observe() {
        guard !observing else { return }
        observing = true
        NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.reload()
            }
        }
    }

    private func resolve(_ type: EKEntityType) async -> Bool {
        let status = EKEventStore.authorizationStatus(for: type)
        if isAllowed(status) { return true }
        if status == .denied || status == .restricted { return false }
        if status == .notDetermined {
            return await request(type)
        }
        return false
    }

    private func isAllowed(_ status: EKAuthorizationStatus) -> Bool {
        if status == .authorized { return true }
        if #available(iOS 17.0, *) {
            return status == .fullAccess
        }
        return false
    }

    private func request(_ type: EKEntityType) async -> Bool {
        if #available(iOS 17.0, *) {
            do {
                if type == .event {
                    return try await store.requestFullAccessToEvents()
                }
                return try await store.requestFullAccessToReminders()
            } catch {
                return false
            }
        }
        return await withCheckedContinuation { continuation in
            store.requestAccess(to: type) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }

    private func loadEvents(now: Date) -> [AgendaEntry] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? now
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate)
            .filter { event in
                guard event.status != .canceled else { return false }
                if event.isAllDay { return true }
                return (event.endDate ?? .distantPast) > now
            }
            .sorted { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }
            .map { event in
                AgendaEntry(
                    id: event.eventIdentifier ?? UUID().uuidString,
                    title: event.title?.isEmpty == false ? event.title! : "Event",
                    schedule: event.isAllDay ? "All day" : (event.startDate ?? now).formatted(date: .omitted, time: .shortened),
                    kind: .event
                )
            }
    }

    private func loadReminders(now: Date) async -> [AgendaEntry] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? now
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: end, calendars: nil)
        let reminders: [EKReminder] = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { items in
                continuation.resume(returning: items ?? [])
            }
        }
        return reminders
            .sorted { lhs, rhs in
                let left = dueDate(lhs) ?? .distantFuture
                let right = dueDate(rhs) ?? .distantFuture
                return left < right
            }
            .map { reminder in
                let due = dueDate(reminder)
                let schedule: String
                if let due, due < start {
                    schedule = "Overdue"
                } else if let due {
                    schedule = due.formatted(date: .omitted, time: .shortened)
                } else {
                    schedule = "Due"
                }
                return AgendaEntry(
                    id: reminder.calendarItemIdentifier,
                    title: reminder.title?.isEmpty == false ? reminder.title! : "Reminder",
                    schedule: schedule,
                    kind: .reminder
                )
            }
    }

    private func dueDate(_ reminder: EKReminder) -> Date? {
        guard let parts = reminder.dueDateComponents else { return nil }
        return Calendar.current.date(from: parts)
    }
}
