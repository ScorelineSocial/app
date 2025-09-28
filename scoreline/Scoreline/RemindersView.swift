//
//  RemindersView.swift
//  Scoreline
//
//  Created by Mehul Jasti on 9/27/25.
//


import SwiftUI
import EventKit

struct RemindersView: View {
    @State private var reminders: [EKReminder] = []
    @State private var isLoading = false
    @State private var rangeDays: Int = 30  // fetch upcoming month of due reminders

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && reminders.isEmpty {
                    ProgressView("Loading reminders…")
                } else if reminders.isEmpty {
                    ContentUnavailableView("No open reminders",
                                           systemImage: "checklist",
                                           description: Text("Everything’s done—nice!"))
                } else {
                    List {
                        ForEach(groupedByDay(reminders), id: \.key) { day, items in
                            Section(day != nil ? Formatter.eventDateOnly.string(from: day!) : "No Due Date") {
                                ForEach(items, id: \.calendarItemIdentifier) { reminder in
                                    NavigationLink {
                                        ReminderDetailView(reminder: reminder)
                                    } label: {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(reminder.title)
                                                .font(.headline)
                                            if let due = reminder.dueDateComponents?.date {
                                                Text(Formatter.eventDateTime.string(from: due))
                                                    .font(.subheadline)
                                                    .foregroundStyle(.secondary)
                                            }
                                            Text(reminder.calendar.title)
                                                .font(.caption)
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Reminders")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Due Window", selection: $rangeDays) {
                            Text("7 days").tag(7)
                            Text("14 days").tag(14)
                            Text("30 days").tag(30)
                            Text("90 days").tag(90)
                        }
                    } label: {
                        Label("Window", systemImage: "slider.horizontal.3")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await load() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                }
            }
            .task(id: rangeDays) { await load() }
            .refreshable { await load() }
        }
    }

    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        let end = Date.startOfToday.adding(days: rangeDays)
        let fetched = await EventKitStore.shared.fetchIncompleteReminders(dueBefore: end)
        await MainActor.run { self.reminders = fetched }
    }

    private func groupedByDay(_ reminders: [EKReminder]) -> [(key: Date?, value: [EKReminder])] {
        let groups = Dictionary(grouping: reminders) { (rem: EKReminder) -> Date? in
            rem.dueDateComponents?.date.map { Calendar.current.startOfDay(for: $0) }
        }
        // Sort: nil (no due date) last; otherwise chronological
        let keys = groups.keys.sorted { a, b in
            switch (a, b) {
            case (nil, nil): return false
            case (nil, _): return false
            case (_, nil): return true
            default: return a! < b!
            }
        }
        return keys.map { ($0, groups[$0]!.sorted { ($0.dueDateComponents?.date ?? .distantFuture) < ($1.dueDateComponents?.date ?? .distantFuture) }) }
    }
}
