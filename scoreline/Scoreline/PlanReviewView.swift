//
//  PlanReviewView.swift
//  Scoreline
//
//  Created by Mehul Jasti on 9/27/25.
//

import SwiftUI

struct PlanReviewView: View {
    @Environment(\.dismiss) private var dismiss
    let plan: PlanResponse
    let user: User

    // Editable copy of milestones
    @State private var milestones: [PlanResponse.Milestone]
    @State private var isSaving = false
    @State private var saveMessage: String?

    init(plan: PlanResponse, user: User) {
        self.plan = plan
        self.user = user
        _milestones = State(initialValue: plan.milestones)
    }

    private var totalImportance: Int {
        milestones.reduce(0) { $0 + $1.importancePoints }
    }

    var body: some View {
        List {
            smartSection
            milestonesSection
            workPlanSection
        }
        .navigationTitle("Review Plan")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await save() }
                } label: {
                    if isSaving { ProgressView() } else { Text("Approve & Save") }
                }
                .disabled(isSaving || milestones.isEmpty)
            }
        }
        .alert("Save",
               isPresented: Binding(
                    get: { saveMessage != nil },
                    set: { newValue in if !newValue { saveMessage = nil } })
        ) {
            Button("OK") {
                if (saveMessage ?? "").contains("Saved") { dismiss() }
            }
        } message: {
            Text(saveMessage ?? "")
        }
    }
}

// MARK: - Sections (split to make type-checking fast)

private extension PlanReviewView {
    @ViewBuilder
    var smartSection: some View {
        Section("SMART Goal") {
            Text(plan.smartGoal.statement)
            Text("Specific: \(plan.smartGoal.specific)").font(.footnote)
            Text("Measurable: \(plan.smartGoal.measurable)").font(.footnote)
            Text("Achievable: \(plan.smartGoal.achievable)").font(.footnote)
            Text("Relevant: \(plan.smartGoal.relevant)").font(.footnote)
            Text("Time-bound: \(plan.smartGoal.timeBound)").font(.footnote)
        }
    }

    @ViewBuilder
    var milestonesSection: some View {
        Section("Milestones · \(totalImportance)/1000 importance") {
            if totalImportance != 1000 {
                Text("Note: current total importance is \(totalImportance). Server-normalized plans always sum to 1000.")
                    .font(.caption)
                    .foregroundColor(totalImportance == 1000 ? .secondary : .orange)
            }

            ForEach($milestones) { $m in
                MilestoneRow(milestone: $m)
            }
            .onDelete { idx in
                milestones.remove(atOffsets: idx)
            }

            Button {
                let new = PlanResponse.Milestone(
                    stableKey: UUID().uuidString,
                    reminderIdentifier: nil,
                    title: "New milestone",
                    notes: nil,
                    due: nil,
                    isCompleted: false,
                    importancePoints: 0
                )
                milestones.append(new)
            } label: {
                Label("Add Milestone", systemImage: "plus.circle")
            }
        }
    }

    @ViewBuilder
    var workPlanSection: some View {
        Section("Daily Work Plan") {
            ForEach(plan.workPlan) { day in
                VStack(alignment: .leading, spacing: 6) {
                    Text(day.date).font(.subheadline).bold()
                    ForEach(day.blocks) { b in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(b.focus).font(.body)
                            Text("\(short(b.start)) → \(short(b.end))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(8)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

// MARK: - Row subviews

private struct MilestoneRow: View {
    @Binding var milestone: PlanResponse.Milestone

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                TextField("Title", text: $milestone.title)
                    .font(.headline)
                Spacer(minLength: 8)
                // Importance chip
                Text("\(milestone.importancePoints)/1000")
                    .font(.caption2).monospacedDigit()
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color(.systemGray6))
                    .clipShape(Capsule())
                    .accessibilityLabel("Importance \(milestone.importancePoints) of 1000")
            }

            // Visual bar for importance (relative to 1000)
            ProgressView(value: Double(milestone.importancePoints), total: 1000)
                .progressViewStyle(.linear)

            TextField("Notes", text: Binding.fromOptional($milestone.notes, default: ""))

            HStack {
                Text("Due:")
                Spacer()
                Text(dueText(from: milestone.due))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func dueText(from isoMaybe: String?) -> String {
        guard let iso = isoMaybe, let d = PlanningDate.date(fromISO: iso) else { return "—" }
        return Formatter.eventDateTime.string(from: d)
    }
}

// MARK: - Actions & helpers

private extension PlanReviewView {
    func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            // 1) Upsert reminders and obtain identifiers for each milestone
            let saved = try await RemindersService.shared.upsertMilestonesReturningIDs(milestones, toListNamed: "Scoreline")
            let idByKey: [String: RemindersService.SavedReminder] = Dictionary(uniqueKeysWithValues: saved.map { ($0.stableKey, $0) })

            // 2) Build POST body for backend (include reminder IDs)
            let planBody = PostMilestonesBody.Plan(
                goal: plan.smartGoal.statement,
                timeframeStart: plan.input.timeframe.start,
                timeframeEnd: plan.input.timeframe.end,
                smartSpecific: plan.smartGoal.specific,
                smartMeasurable: plan.smartGoal.measurable,
                smartAchievable: plan.smartGoal.achievable,
                smartRelevant: plan.smartGoal.relevant,
                smartTimeBound: plan.smartGoal.timeBound
            )

            let milestoneBodies: [PostMilestonesBody.Milestone] = milestones.map { m in
                let ids = idByKey[m.stableKey]
                return PostMilestonesBody.Milestone(
                    stableKey: m.stableKey,
                    title: m.title,
                    notes: m.notes,
                    due: m.due,
                    importancePoints: m.importancePoints,
                    isCompleted: m.isCompleted,
                    reminderIdentifier: ids?.reminderIdentifier,
                    reminderExternalIdentifier: ids?.reminderExternalIdentifier
                )
            }

            let body = PostMilestonesBody(
                plan: planBody,
                milestones: milestoneBodies,
                normalizeImportance: true,
                activatePlan: true
            )

            // 3) POST to backend
            let res = try await APIClient.shared.postMilestones(body: body)

            // 4) Let user know; your alert already dismisses view on "Saved"
            let awardedPart = (res.pointsAwarded ?? 0) > 0 ? " (+\(res.pointsAwarded!) pts)" : ""
            saveMessage = "Saved plan and \(res.milestones.count) milestone(s)\(awardedPart)."
        } catch {
            saveMessage = "Failed to save: \(error.localizedDescription)"
        }
    }

    func short(_ iso: String) -> String {
        if let d = PlanningDate.date(fromISO: iso) { return Formatter.eventDateTime.string(from: d) }
        return iso
    }
}

// MARK: - Binding helpers

private extension Binding where Value == String {
    /// Create a Binding<String> from Binding<String?>, substituting a default for nil, and writing back nil when empty.
    static func fromOptional(_ source: Binding<String?>, default defaultValue: String) -> Binding<String> {
        Binding<String>(
            get: { source.wrappedValue ?? defaultValue },
            set: { newValue in
                source.wrappedValue = newValue.isEmpty ? nil : newValue
            }
        )
    }
}
