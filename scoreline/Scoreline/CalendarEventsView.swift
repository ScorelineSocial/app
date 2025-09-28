//
//  CalendarEventsView.swift
//  Scoreline
//
//  Created by Mehul Jasti on 9/27/25.
//


import SwiftUI
import EventKit

struct CalendarEventsView: View {
    @State private var events: [EKEvent] = []
    @State private var isLoading = false
    @State private var rangeDays: Int = 14  // show 2 weeks by default

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && events.isEmpty {
                    ProgressView("Loading events…")
                } else if events.isEmpty {
                    ContentUnavailableView("No upcoming events",
                                           systemImage: "calendar",
                                           description: Text("You’re all caught up."))
                } else {
                    List {
                        ForEach(groupedByDay(events), id: \.key) { day, items in
                            Section(Formatter.eventDateOnly.string(from: day)) {
                                ForEach(items, id: \.eventIdentifier) { event in
                                    NavigationLink {
                                        EventDetailView(event: event)
                                    } label: {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(event.title)
                                                .font(.headline)
                                            Text("\(Formatter.eventDateTime.string(from: event.startDate)) – \(Formatter.eventDateTime.string(from: event.endDate))")
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                            Text(event.calendar.title)
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
            .navigationTitle("Calendar")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Range", selection: $rangeDays) {
                            Text("7 days").tag(7)
                            Text("14 days").tag(14)
                            Text("30 days").tag(30)
                        }
                    } label: {
                        Label("Range", systemImage: "slider.horizontal.3")
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

        let start = Date.startOfToday
        let end = start.adding(days: rangeDays)
        let fetched = EventKitStore.shared.fetchEvents(from: start, to: end)
        await MainActor.run { self.events = fetched }
    }

    private func groupedByDay(_ events: [EKEvent]) -> [(key: Date, value: [EKEvent])] {
        let groups = Dictionary(grouping: events) { event in
            Calendar.current.startOfDay(for: event.startDate)
        }
        return groups.keys.sorted().map { ($0, groups[$0]!.sorted { $0.startDate < $1.startDate }) }
    }
}
