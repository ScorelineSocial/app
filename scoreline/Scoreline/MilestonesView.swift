//
//  MilestonesView.swift
//  Scoreline
//
//  Created by Mehul Jasti on 9/28/25.
//

import SwiftUI
import EventKit

struct MilestonesView: View {
    @State private var plan: PlanDTO?
    @State private var allMilestones: [MilestoneDTO] = []
    @State private var loading = true
    @State private var error: String?
    @State private var refreshing = false

    enum Filter: String, CaseIterable, Identifiable {
        case open = "Open"
        case all = "All"
        case done = "Done"
        var id: String { rawValue }
    }
    @State private var filter: Filter = .open

    private var filtered: [MilestoneDTO] {
        switch filter {
        case .open: return allMilestones.filter { !$0.isCompleted }
        case .done: return allMilestones.filter { $0.isCompleted }
        case .all:  return allMilestones
        }
    }

    private var totalCoins: Int {
        allMilestones.reduce(0) { $0 + $1.importancePoints }
    }

    private var completedCoins: Int {
        allMilestones.filter { $0.isCompleted }.reduce(0) { $0 + $1.importancePoints }
    }
    
    private var progressPercentLabel: String {
        let pct = totalCoins > 0 ? Int(round(Double(completedCoins) / Double(totalCoins) * 100)) : 0
        return "\(completedCoins)/\(max(totalCoins, 0)) coins (\(pct)%)"
    }

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("Loading…").font(.footnote).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let err = error {
                    VStack(spacing: 10) {
                        Text("Something went wrong").font(.headline)
                        Text(err).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Button("Retry") { Task { await load() } }
                            .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            headerCard
                            Picker("Filter", selection: $filter) {
                                ForEach(Filter.allCases) { f in Text(f.rawValue).tag(f) }
                            }
                            .pickerStyle(.segmented)
                            ForEach(filtered, id: \.id) { m in
                                MilestoneRow(
                                    milestone: m,
                                    onToggle: { newValue in
                                        Task { await toggleCompletion(m, to: newValue) }
                                    }
                                )
                            }
                            if filtered.isEmpty {
                                Text("Nothing here yet.")
                                    .frame(maxWidth: .infinity)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 24)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .refreshable { await refresh() }
                    }
                }
            }
            .navigationTitle("Milestones")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await refresh() }
                    } label: {
                        if refreshing { ProgressView() } else { Image(systemName: "arrow.clockwise.circle") }
                    }
                    .disabled(refreshing)
                }
            }
        }
        .task { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .milestonesSynced)) { _ in
            Task { await load(preserveFilter: true) }
        }
    }
}

private extension MilestonesView {
    @ViewBuilder
    var headerCard: some View {
        if let p = plan {
            VStack(alignment: .leading, spacing: 8) {
                Text(p.goal)
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 12) {
                    if let s = p.timeframeStart, let e = p.timeframeEnd, !s.isEmpty, !e.isEmpty {
                        Text("\(s) → \(e)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                if let specific = p.smartSpecific, !specific.isEmpty {
                    Text("Specific: \(specific)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: Double(completedCoins), total: Double(max(totalCoins, 1)))
                        .progressViewStyle(.linear)
                    Text(progressPercentLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Progress \(progressPercentLabel)")
                }
                .padding(.top, 6)
            }
            .padding(12)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

private struct MilestoneRow: View {
    let milestone: MilestoneDTO
    let onToggle: (Bool) -> Void

    var body: some View {
        Button {
            onToggle(!milestone.isCompleted)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                // Top: checkbox + title
                HStack(spacing: 10) {
                    Image(systemName: milestone.isCompleted ? "checkmark.circle.fill" : "circle")
                        .imageScale(.large)
                        .symbolRenderingMode(.hierarchical)
                    Text(milestone.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }

                // Bottom: date (left) + coins (right)
                HStack {
                    Text(formattedDate(milestone))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Text("\(milestone.importancePoints) coins")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func formattedDate(_ m: MilestoneDTO) -> String {
        if m.isCompleted, let c = m.completedAt, let d = PlanningDate.date(fromISO: c) {
            return Formatter.eventDateTime.string(from: d)
        }
        if let due = m.dueTs, let d = PlanningDate.date(fromISO: due) {
            return Formatter.eventDateTime.string(from: d)
        }
        return ""
    }
}

private extension MilestonesView {
    func load(preserveFilter: Bool = false) async {
        if !preserveFilter {
            await MainActor.run {
                loading = true
                error = nil
            }
        }
        do {
            let status: APIClient.StatusFilter = {
                switch filter {
                case .open: return .open
                case .done: return .completed
                case .all:  return .all
                }
            }()
            do {
                let (p, ms) = try await APIClient.shared.getActivePlanWithMilestones(status: status)
                await MainActor.run {
                    self.plan = p
                    self.allMilestones = ms
                    self.loading = false
                }
            } catch let err {
                await MainActor.run {
                    self.error = err.localizedDescription
                    self.loading = false
                }
            }
        }
    }

    func refresh() async {
        await MainActor.run { refreshing = true }
        defer { Task { await MainActor.run { refreshing = false } } }
        await MilestonesSyncManager.shared.syncOnForeground()
        await load(preserveFilter: true)
    }

    func toggleCompletion(_ m: MilestoneDTO, to newValue: Bool) async {
        // optimistic
        if let idx = allMilestones.firstIndex(where: { $0.id == m.id }) {
            allMilestones[idx] = updated(m, isCompleted: newValue, completedAtISO: newValue ? PlanningDate.iso8601Z.string(from: Date()) : nil)
        }

        do {
            let body = PatchMilestoneBody(
                isCompleted: newValue,
                completedAt: newValue ? .some(PlanningDate.iso8601Z.string(from: Date())) : .some(nil)
            )
            _ = try await APIClient.shared.patchMilestone(id: m.id, body: body)
            await markReminder(stableKey: m.stableKey, isCompleted: newValue, completedAtISO: newValue ? PlanningDate.iso8601Z.string(from: Date()) : nil)
        } catch let err {
            if let idx = allMilestones.firstIndex(where: { $0.id == m.id }) {
                allMilestones[idx] = updated(m, isCompleted: !newValue, completedAtISO: !newValue ? nil : PlanningDate.iso8601Z.string(from: Date()))
            }
            await MainActor.run { self.error = "Failed to update: \(err.localizedDescription)" }
        }
    }

    func updated(_ m: MilestoneDTO, isCompleted: Bool, completedAtISO: String?) -> MilestoneDTO {
        MilestoneDTO(
            id: m.id,
            appleSub: m.appleSub,
            planId: m.planId,
            stableKey: m.stableKey,
            title: m.title,
            notes: m.notes,
            dueTs: m.dueTs,
            importancePoints: m.importancePoints,
            isCompleted: isCompleted,
            completedAt: completedAtISO,
            completedSource: m.completedSource,
            reminderIdentifier: m.reminderIdentifier,
            reminderExternalIdentifier: m.reminderExternalIdentifier,
            lastSyncedAt: m.lastSyncedAt,
            createdAt: m.createdAt,
            updatedAt: m.updatedAt
        )
    }

    func markReminder(stableKey: String, isCompleted: Bool, completedAtISO: String?) async {
        do {
            _ = try await RemindersService.shared.ensureAccess()
            let calendar = try await RemindersService.shared.getOrCreateRemindersList(named: "Scoreline")
            let map = try await RemindersService.shared.fetchRemindersByStableKey(in: calendar)
            guard let r = map[stableKey] else { return }
            if isCompleted {
                r.isCompleted = true
                if let iso = completedAtISO, let dt = PlanningDate.date(fromISO: iso) {
                    r.completionDate = dt
                } else {
                    r.completionDate = Date()
                }
            } else {
                r.isCompleted = false
                r.completionDate = nil
            }
            try await RemindersService.shared.saveExisting(reminder: r)
        } catch {
            #if DEBUG
            print("⚠️ markReminder failed: \(error.localizedDescription)")
            #endif
        }
    }
}
