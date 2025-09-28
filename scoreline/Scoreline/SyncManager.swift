//
//  SyncManager.swift
//  Scoreline
//
//  Created by Mehul Jasti on 9/27/25.
//

import Foundation
import EventKit
import CryptoKit

@MainActor
final class SyncManager {
    static let shared = SyncManager()
    private let store = EKEventStore()

    struct ProgressState: Sendable {
        var eventsDone: Int = 0
        var eventsTotal: Int = 0
        var remindersDone: Int = 0
        var remindersTotal: Int = 0
    }

    private var progressState = ProgressState()

    func syncIncremental(
        api: APIClient,
        yearsAhead: Int = 10,
        onProgress: @escaping @MainActor @Sendable (ProgressState) -> Void
    ) async throws {
        // 🔐 Make sure we have a valid access token (will try refresh if needed)
        try await api.ensureAuthenticated()

        try await store.requestFullAccessToEvents()
        try await store.requestFullAccessToReminders()

        let now = Date()
        let end = Calendar.current.date(byAdding: .year, value: yearsAhead, to: now)!

        let events = fetchEvents(from: now, to: end).map(SyncEvent.init)
        let reminders = try await fetchFutureReminders().map(SyncReminder.init)

        progressState = ProgressState(
            eventsDone: 0, eventsTotal: events.count,
            remindersDone: 0, remindersTotal: reminders.count
        )
        onProgress(progressState)

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await self.pushEvents(api: api, events: events) {
                    await MainActor.run {
                        self.progressState.eventsDone += 1
                        onProgress(self.progressState)
                    }
                }
            }
            group.addTask {
                try await self.pushReminders(api: api, reminders: reminders) {
                    await MainActor.run {
                        self.progressState.remindersDone += 1
                        onProgress(self.progressState)
                    }
                }
            }
            try await group.waitForAll()
        }
    }

    // MARK: Pushers

    private func pushEvents(
        api: APIClient,
        events: [SyncEvent],
        onItem: @Sendable @escaping () async -> Void
    ) async throws {
        for e in events {
            let payload = EventUpsert(
                stableKey: e.stableKey,
                calendarId: e.calendarId,
                eventIdentifier: e.eventIdentifier,
                title: e.title,
                notes: e.notes,
                start: e.start,
                end: e.end,
                allDay: e.allDay,
                isBusy: e.isBusy
            )

            try await retrying(times: 3) {
                struct Resp: Decodable { let ok: Bool }
                let _: Resp = try await api.postJSON("api/sync/event", body: payload)
            }
            await onItem()
        }
    }

    private func pushReminders(
        api: APIClient,
        reminders: [SyncReminder],
        onItem: @Sendable @escaping () async -> Void
    ) async throws {
        for r in reminders {
            let payload = ReminderUpsert(
                stableKey: r.stableKey,
                reminderIdentifier: r.reminderIdentifier,
                title: r.title,
                notes: r.notes,
                due: r.due,
                isCompleted: r.isCompleted
            )

            try await retrying(times: 3) {
                struct Resp: Decodable { let ok: Bool }
                let _: Resp = try await api.postJSON("api/sync/reminder", body: payload)
            }
            await onItem()
        }
    }

    // MARK: EventKit fetch (MainActor)

    private func fetchEvents(from start: Date, to end: Date) -> [EKEvent] {
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).sorted { $0.startDate < $1.startDate }
    }

    private func fetchFutureReminders() async throws -> [EKReminder] {
        let pred = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        let all = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[EKReminder], Error>) in
            store.fetchReminders(matching: pred) { cont.resume(returning: $0 ?? []) }
        }
        return all
            .filter { r in
                if let due = r.dueDateComponents?.date { return due >= Date() }
                return true
            }
            .sorted { (a, b) in
                (a.dueDateComponents?.date ?? .distantFuture) < (b.dueDateComponents?.date ?? .distantFuture)
            }
    }

    // MARK: Wire types (DTOs)

    struct SyncEvent: Encodable, Sendable {
        let stableKey: String
        let calendarId: String
        let eventIdentifier: String?
        let title: String?
        let notes: String?
        let start: String
        let end: String
        let allDay: Bool
        let isBusy: Bool

        init(_ e: EKEvent) {
            let calId = e.calendar.calendarIdentifier
            let occStart = e.startDate.utcISO8601
            self.stableKey = "\(calId)|\(occStart)|\(e.eventIdentifier ?? "")".sha256()
            self.calendarId = calId
            self.eventIdentifier = e.eventIdentifier
            self.title = e.title
            self.notes = e.notes
            self.start = e.startDate.utcISO8601
            self.end = e.endDate.utcISO8601
            self.allDay = e.isAllDay
            self.isBusy = true
        }
    }

    struct SyncReminder: Encodable, Sendable {
        let stableKey: String
        let reminderIdentifier: String?
        let title: String?
        let notes: String?
        let due: String?
        let isCompleted: Bool

        init(_ r: EKReminder) {
            let calId = r.calendar.calendarIdentifier
            let created = r.creationDate?.utcISO8601 ?? ""
            self.stableKey = "\(calId)|\(created)|\(r.calendarItemIdentifier)".sha256()
            self.reminderIdentifier = r.calendarItemIdentifier
            self.title = r.title
            self.notes = r.notes
            self.due = r.dueDateComponents?.date?.utcISO8601
            self.isCompleted = r.isCompleted
        }
    }

    // Payloads the API expects (NO appleSub; server reads sub from token)
    struct EventUpsert: Encodable, Sendable {
        let stableKey: String
        let calendarId: String
        let eventIdentifier: String?
        let title: String?
        let notes: String?
        let start: String
        let end: String
        let allDay: Bool
        let isBusy: Bool
    }

    struct ReminderUpsert: Encodable, Sendable {
        let stableKey: String
        let reminderIdentifier: String?
        let title: String?
        let notes: String?
        let due: String?
        let isCompleted: Bool
    }
}

// MARK: - Helpers

private extension Date {
    var utcISO8601: String {
        let f = ISO8601DateFormatter()
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f.string(from: self)
    }
}

private extension String {
    func sha256() -> String {
        let digest = SHA256.hash(data: Data(self.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Retry util with backoff

private func retrying<T>(
    times: Int,
    initialDelay: UInt64 = 200_000_000, // 0.2s
    factor: Double = 2.0,
    _ op: @escaping @Sendable () async throws -> T
) async throws -> T {
    var attempt = 0
    var delay = initialDelay
    while true {
        do { return try await op() }
        catch {
            attempt += 1
            if attempt >= times { throw error }
            try? await Task.sleep(nanoseconds: delay)
            delay = UInt64(Double(delay) * factor)
        }
    }
}
