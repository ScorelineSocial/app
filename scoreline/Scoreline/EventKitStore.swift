//
//  EventKitStore.swift
//  Scoreline
//
//  Created by Mehul Jasti on 9/27/25.
//


import Foundation
import EventKit

@MainActor
final class EventKitStore {
    static let shared = EventKitStore()
    private let store = EKEventStore()

    // Fetch calendar events in a date range
    func fetchEvents(from start: Date, to end: Date) -> [EKEvent] {
        let calendars = store.calendars(for: .event)
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        // Sorted by start date by default; keep it stable
        return store.events(matching: predicate).sorted { $0.startDate < $1.startDate }
    }

    // Fetch reminders (incomplete + those due soon)
    func fetchIncompleteReminders(dueBefore end: Date?) async -> [EKReminder] {
        await withCheckedContinuation { continuation in
            let calendars = store.calendars(for: .reminder)
            let predicate: NSPredicate
            if let end {
                predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: end, calendars: calendars)
            } else {
                predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: calendars)
            }

            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: (reminders ?? []).sorted(by: { lhs, rhs in
                    (lhs.dueDateComponents?.date ?? .distantFuture) < (rhs.dueDateComponents?.date ?? .distantFuture)
                }))
            }
        }
    }
}

extension DateComponents {
    var date: Date? { Calendar.current.date(from: self) }
}

extension Date {
    static var startOfToday: Date {
        Calendar.current.startOfDay(for: Date())
    }

    func adding(days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: self) ?? self
    }
}

extension Formatter {
    static let eventDateTime: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df
    }()

    static let eventDateOnly: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none
        return df
    }()
}
