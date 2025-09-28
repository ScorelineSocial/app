//
//  EventDetailView.swift
//  Scoreline
//
//  Created by Mehul Jasti on 9/27/25.
//


import SwiftUI
import EventKit

struct EventDetailView: View {
    let event: EKEvent

    var body: some View {
        List {
            Section("Info") {
                LabeledContent("Title", value: event.title)
                if let loc = event.location, !loc.isEmpty {
                    LabeledContent("Location", value: loc)
                }
                LabeledContent("Calendar", value: event.calendar.title)
                LabeledContent("All-day", value: event.isAllDay ? "Yes" : "No")
                LabeledContent("Starts", value: Formatter.eventDateTime.string(from: event.startDate))
                LabeledContent("Ends", value: Formatter.eventDateTime.string(from: event.endDate))
                if let url = event.url {
                    Link(destination: url) { LabeledContent("URL", value: url.absoluteString) }
                }
            }

            if let attendees = event.attendees, !attendees.isEmpty {
                Section("Attendees") {
                    ForEach(attendees, id: \.self) { att in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(att.name ?? "Unknown")
                            Text(att.url.absoluteString)
                                .foregroundStyle(.secondary)
                                .font(.caption)
                            Text(att.participantStatus.description)
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                    }
                }
            }


            if let notes = event.notes, !notes.isEmpty {
                Section("Notes") {
                    Text(notes)
                }
            }
        }
        .navigationTitle("Event")
    }
}

private extension EKParticipantStatus {
    var description: String {
        switch self {
        case .accepted: return "Accepted"
        case .declined: return "Declined"
        case .tentative: return "Tentative"
        case .pending: return "Pending"
        default: return "Unknown"
        }
    }
}
