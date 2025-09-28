//
//  ReminderDetailView.swift
//  Scoreline
//
//  Created by Mehul Jasti on 9/27/25.
//


import SwiftUI
import EventKit

struct ReminderDetailView: View {
    let reminder: EKReminder

    var body: some View {
        List {
            Section("Info") {
                LabeledContent("Title", value: reminder.title)
                LabeledContent("List", value: reminder.calendar.title)
                if let start = reminder.startDateComponents?.date {
                    LabeledContent("Start", value: Formatter.eventDateTime.string(from: start))
                }
                if let due = reminder.dueDateComponents?.date {
                    LabeledContent("Due", value: Formatter.eventDateTime.string(from: due))
                }
                LabeledContent("Priority", value: priorityText(reminder.priority))
                LabeledContent("Completed", value: reminder.isCompleted ? "Yes" : "No")
                if let completed = reminder.completionDate {
                    LabeledContent("Completed On", value: Formatter.eventDateTime.string(from: completed))
                }
                if let url = reminder.url {
                    Link(destination: url) { LabeledContent("URL", value: url.absoluteString) }
                }
            }

            if let notes = reminder.notes, !notes.isEmpty {
                Section("Notes") {
                    Text(notes)
                }
            }

            if let alarms = reminder.alarms, !alarms.isEmpty {
                Section("Alarms") {
                    ForEach(alarms.indices, id: \.self) { i in
                        let alarm = alarms[i]
                        if let date = alarm.absoluteDate {
                            Text("Alarm \(i+1): \(Formatter.eventDateTime.string(from: date))")
                        } else if let off = alarm.relativeOffset as Double? {
                            Text("Alarm \(i+1): relative \(Int(off))s")
                        } else {
                            Text("Alarm \(i+1)")
                        }
                    }
                }
            }
        }
        .navigationTitle("Reminder")
    }

    private func priorityText(_ p: Int) -> String {
        // 0 none, 1 high ... 9 low per Reminders semantics
        switch p {
        case 1...3: return "High (\(p))"
        case 4...6: return "Medium (\(p))"
        case 7...9: return "Low (\(p))"
        default: return "None"
        }
    }
}
