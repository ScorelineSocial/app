//
//  RemindersService.swift
//  Scoreline
//
//  Created by Mehul Jasti on 9/27/25.
//

import Foundation
import EventKit

public enum RemindersServiceError: Error, LocalizedError {
    case accessDenied
    case noWritableSource
    case calendarNotFound(String)
    case invalidStableKey
    case cannotFindCalendarOrReminder

    public var errorDescription: String? {
        switch self {
        case .accessDenied: return "Reminders access was denied."
        case .noWritableSource: return "No writable Reminders source is available."
        case .calendarNotFound(let name): return "Reminders list '\(name)' was not found."
        case .invalidStableKey: return "Invalid milestone stable key."
        case .cannotFindCalendarOrReminder: return "Could not locate the Scoreline list or requested reminder."
        }
    }
}

public final class RemindersService {
    public static let shared = RemindersService()
    private let store = EKEventStore()

    private init() {}

    // MARK: - Authorization

    @discardableResult
    public func ensureAccess() async throws -> Bool {
        if #available(iOS 17, *) {
            let granted = try await store.requestFullAccessToReminders()
            if !granted { throw RemindersServiceError.accessDenied }
            return granted
        } else {
            return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Bool, Error>) in
                store.requestAccess(to: .reminder) { granted, error in
                    if let error { cont.resume(throwing: error); return }
                    if !granted { cont.resume(throwing: RemindersServiceError.accessDenied); return }
                    cont.resume(returning: true)
                }
            }
        }
    }

    // MARK: - Calendars (Lists)

    public func remindersList(named name: String) -> EKCalendar? {
        store.calendars(for: .reminder).first { $0.title == name && $0.allowsContentModifications }
    }

    public func defaultRemindersList() -> EKCalendar? {
        store.defaultCalendarForNewReminders()
    }

    @discardableResult
    public func getOrCreateRemindersList(named name: String) async throws -> EKCalendar {
        try await ensureAccess()

        if let existing = remindersList(named: name) { return existing }

        // Choose a source—prefer the default calendar's source; fall back to iCloud/local/Exchange/any
        let source: EKSource? =
            store.defaultCalendarForNewReminders()?.source ??
            store.sources.first(where: { $0.sourceType == .calDAV && $0.title.lowercased().contains("icloud") }) ??
            store.sources.first(where: { $0.sourceType == .local }) ??
            store.sources.first(where: { $0.sourceType == .exchange }) ??
            store.sources.first

        guard let chosen = source else { throw RemindersServiceError.noWritableSource }

        let cal = EKCalendar(for: .reminder, eventStore: store)
        cal.title = name
        cal.source = chosen

        try store.saveCalendar(cal, commit: true)
        return cal
    }

    // MARK: - Legacy (kept for compatibility)

    /// Save planning milestones as EKReminders to the given list name (created if missing).
    /// Returns created reminders (no identifier mapping). Prefer `upsertMilestonesReturningIDs`.
    @discardableResult
    public func saveMilestones(_ milestones: [PlanResponse.Milestone], toListNamed listName: String = "Scoreline") async throws -> [EKReminder] {
        try await ensureAccess()
        let calendar = try await getOrCreateRemindersList(named: listName)

        var saved: [EKReminder] = []
        for m in milestones {
            let r = EKReminder(eventStore: store)
            r.calendar = calendar
            r.title = m.title
            r.notes = m.notes
            // Tag with stableKey for future lookups
            r.url = Self.urlForStableKey(m.stableKey)

            if let dueStr = m.due, let dueDate = PlanningDate.date(fromISO: dueStr) {
                r.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: dueDate)
                r.addAlarm(EKAlarm(absoluteDate: dueDate))
            }

            try store.save(r, commit: false)
            saved.append(r)
        }

        try store.commit()
        return saved
    }

    // MARK: - New: Upsert milestones and return IDs

    /// A compact mapping to send to the server after creating/updating reminders.
    public struct SavedReminder: Hashable {
        public let stableKey: String
        public let reminderIdentifier: String
        public let reminderExternalIdentifier: String?
    }

    /// Creates or updates reminders for the given milestones inside the Scoreline list (or provided list),
    /// tagging each reminder with `scoreline://milestone/<stableKey>` in `url`,
    /// and returns identifiers you can POST with the milestones to the server.
    @discardableResult
    public func upsertMilestonesReturningIDs(
        _ milestones: [PlanResponse.Milestone],
        toListNamed listName: String = "Scoreline"
    ) async throws -> [SavedReminder] {
        try await ensureAccess()
        let calendar = try await getOrCreateRemindersList(named: listName)

        // Build a map of existing reminders in this calendar keyed by stableKey parsed from url.
        let existingByKey = try await fetchRemindersByStableKey(in: calendar)

        var results: [SavedReminder] = []
        for m in milestones {
            let reminder: EKReminder
            if let existing = existingByKey[m.stableKey] {
                reminder = existing
            } else {
                reminder = EKReminder(eventStore: store)
                reminder.calendar = calendar
                reminder.url = Self.urlForStableKey(m.stableKey)
            }

            // Update fields
            reminder.title = m.title
            reminder.notes = m.notes

            // Due (date-only or date-time)
            if let dueStr = m.due, let dueDate = PlanningDate.date(fromISO: dueStr) {
                reminder.dueDateComponents = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute, .second], from: dueDate
                )
                // Clear existing alarms to avoid duplicates; then add one alarm at due date.
                if let alarms = reminder.alarms { for a in alarms { reminder.removeAlarm(a) } }
                reminder.addAlarm(EKAlarm(absoluteDate: dueDate))
            } else {
                reminder.dueDateComponents = nil
                if let alarms = reminder.alarms { for a in alarms { reminder.removeAlarm(a) } }
            }

            // Completion state is UI-only at creation; we do not auto-complete here.

            try store.save(reminder, commit: false)

            // We'll read identifiers after commit below
            results.append(
                SavedReminder(
                    stableKey: m.stableKey,
                    reminderIdentifier: reminder.calendarItemIdentifier,
                    reminderExternalIdentifier: reminder.calendarItemExternalIdentifier
                )
            )
        }

        try store.commit()
        return results
    }

    // MARK: - Sync helpers

    /// Fetches Scoreline reminders (both incomplete and completed, wide window) and returns a map by stableKey.
    public func fetchRemindersByStableKey(in calendar: EKCalendar) async throws -> [String: EKReminder] {
        var all: [EKReminder] = []
        // Incomplete
        let incomplete = await fetchIncompleteReminders(calendars: [calendar], dueBefore: nil)
        all.append(contentsOf: incomplete)

        // Completed — choose a wide time window
        let start = Date(timeIntervalSince1970: 0)
        let end   = Date().addingTimeInterval(60 * 60 * 24 * 365 * 10) // +10y
        let completed = await fetchCompletedReminders(calendars: [calendar], from: start, to: end)
        all.append(contentsOf: completed)

        var map: [String: EKReminder] = [:]
        for r in all {
            if let key = Self.stableKey(from: r) {
                map[key] = r
            }
        }
        return map
    }

    /// Builds deltas suitable for POST /api/milestones/sync by scanning the Scoreline list.
    public func collectCompletionDeltas(
        listName: String = "Scoreline"
    ) async throws -> [SyncDelta] {
        try await ensureAccess()
        guard let calendar = remindersList(named: listName) else {
            throw RemindersServiceError.calendarNotFound(listName)
        }

        let map = try await fetchRemindersByStableKey(in: calendar)
        var deltas: [SyncDelta] = []
        deltas.reserveCapacity(map.count)

        for (key, r) in map {
            let completedAtISO: String? = {
                if let dt = r.completionDate { return PlanningDate.iso8601Z.string(from: dt) }
                return nil
            }()
            deltas.append(
                SyncDelta(
                    stableKey: key,
                    isCompleted: r.isCompleted,
                    completedAt: completedAtISO,
                    reminderIdentifier: r.calendarItemIdentifier,
                    reminderExternalIdentifier: r.calendarItemExternalIdentifier
                )
            )
        }
        return deltas
    }
    
    /// Saves an already-fetched EKReminder using the service's internal EKEventStore.
    public func saveExisting(reminder: EKReminder) async throws {
        try store.save(reminder, commit: true)
    }

    // MARK: - Low-level Reminders fetching

    /// Internal: fetches incomplete reminders for calendars (optionally filter by dueBefore).
    private func fetchIncompleteReminders(calendars: [EKCalendar], dueBefore end: Date?) async -> [EKReminder] {
        await withCheckedContinuation { continuation in
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

    /// Internal: fetches completed reminders for calendars in a date range.
    private func fetchCompletedReminders(calendars: [EKCalendar], from start: Date?, to end: Date?) async -> [EKReminder] {
        await withCheckedContinuation { continuation in
            let predicate = store.predicateForCompletedReminders(withCompletionDateStarting: start, ending: end, calendars: calendars)
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: (reminders ?? []))
            }
        }
    }

    // MARK: - StableKey tagging

    /// We tag reminders with the milestone stableKey via the `url` field for robust lookup across devices.
    private static func urlForStableKey(_ key: String) -> URL? {
        URL(string: "scoreline://milestone/\(key)")
    }

    /// Parse a stableKey from a tagged reminder's URL.
    private static func stableKey(from r: EKReminder) -> String? {
        guard let s = r.url?.absoluteString else { return nil }
        let prefix = "scoreline://milestone/"
        guard s.hasPrefix(prefix) else { return nil }
        return String(s.dropFirst(prefix.count))
    }
}
