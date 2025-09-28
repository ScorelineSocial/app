//
//  HomeView.swift
//  Scoreline
//
//  Created by Mehul Jasti on 9/27/25.
//

import SwiftUI

struct HomeView: View {
    let user: User
    @Environment(SessionViewModel.self) private var session

    // Sync state
    @State private var isSyncing = false
    @State private var syncMessage: String?
    @State private var progress = SyncManager.ProgressState()

    // Planning progress (streaming)
    @State private var planStreaming = false
    @State private var planPct: Double = 0
    @State private var planNote: String = ""

    // Flow mode
    private enum FlowMode: String, CaseIterable, Identifiable {
        case refine = "Refine first"
        case direct = "Plan directly"
        var id: String { rawValue }
    }
    @State private var flowMode: FlowMode = .refine

    // Refine state
    @State private var broadGoal: String = ""
    @State private var refineLoading = false
    @State private var refineError: String?
    @State private var refineResult: RefineResponse?

    @FocusState private var goalFieldFocused: Bool

    // Selection produced by refinement (editable before planning)
    @State private var selectedGoal: String = ""
    @State private var selectedStart: Date = Date()
    @State private var selectedEnd: Date = Calendar.current.date(byAdding: .day, value: 7, to: Date())!

    // Direct planning state
    @State private var directGoal: String = ""
    @State private var directStart: Date = Date()
    @State private var directEnd: Date = Calendar.current.date(byAdding: .day, value: 14, to: Date())!
    @FocusState private var directGoalFocused: Bool

    // Plan state (shared)
    @State private var planLoading = false
    @State private var planError: String?
    @State private var planToReview: PlanResponse?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    syncControls

                    Divider().padding(.vertical, 8)

                    // Flow switcher
                    Picker("Flow", selection: $flowMode) {
                        ForEach(FlowMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    // REFINE FLOW
                    if flowMode == .refine {
                        refineSection

                        if let r = refineResult {
                            proposalEditor(proposal: r.proposal, alternatives: r.alternatives)
                            refinePlanSection  // show "Create Plan" once we have a proposal
                        }
                    }

                    // DIRECT FLOW
                    if flowMode == .direct {
                        directPlanSection
                    }

                    // Streaming progress UI (for both flows)
                    if planStreaming {
                        VStack(spacing: 6) {
                            ProgressView(value: planPct, total: 100)
                            if !planNote.isEmpty {
                                Text(planNote).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.top, 4)
                    }

                    Spacer(minLength: 20)
                }
                .padding()
                .navigationTitle("Grindstone")
                .navigationDestination(item: $planToReview) { plan in
                    PlanReviewView(plan: plan, user: user)
                }
            }
        }
        .onChange(of: flowMode) { _, newValue in
            // Seed direct fields from the broad goal if user switches flows
            if newValue == .direct, directGoal.isEmpty, !broadGoal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                directGoal = broadGoal.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
    }

    // MARK: - Sync UI

    private var syncControls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Button {
                    Task {
                        isSyncing = true
                        syncMessage = nil
                        defer { isSyncing = false }
                        do {
                            try await SyncManager.shared.syncIncremental(
                                api: APIClient.shared,
                                yearsAhead: 10
                            ) { p in
                                progress = p
                            }
                            syncMessage = "Sync complete."
                        } catch {
                            syncMessage = "Sync failed: \(error.localizedDescription)"
                        }
                    }
                } label: {
                    if isSyncing { ProgressView().frame(maxWidth: .infinity) }
                    else { Text("Sync Now (All Future)").frame(maxWidth: .infinity) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSyncing)

                Button("Log Out") { Task { await session.signOut() } }
                    .buttonStyle(.bordered)
            }

            if isSyncing {
                let total = max(1, progress.eventsTotal + progress.remindersTotal)
                let done = progress.eventsDone + progress.remindersDone
                ProgressView(value: Double(done), total: Double(total))
                Text("Events \(progress.eventsDone)/\(progress.eventsTotal) · Reminders \(progress.remindersDone)/\(progress.remindersTotal)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let msg = syncMessage {
                Text(msg).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - REFINE FLOW

    private var refineSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Plan something").font(.headline)
            TextField("What do you want to achieve?", text: $broadGoal)
                .textFieldStyle(.roundedBorder)
                .focused($goalFieldFocused)

            Button {
                // Dismiss keyboard
                goalFieldFocused = false
                Task { await doRefine() }
            } label: {
                if refineLoading { ProgressView() } else { Text("Refine") }
            }
            .buttonStyle(.borderedProminent)
            .disabled(broadGoal.trimmingCharacters(in: .whitespacesAndNewlines).count < 3 || refineLoading)

            if let err = refineError {
                Text(err.components(separatedBy: "\n").first ?? err)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private func doRefine() async {
        refineLoading = true
        refineError = nil
        defer { refineLoading = false }
        do {
            let today = PlanningDate.yyyyMMdd(from: Date())
            let req = RefineRequest(goal: broadGoal, today: today, hints: nil)
            let res = try await APIClient.shared.refine(input: req)
            refineResult = res
            // seed editable selection
            selectedGoal = res.proposal.refinedGoal
            selectedStart = parseYYYYMMDD(res.proposal.timeframe.start) ?? Date()
            selectedEnd = parseYYYYMMDD(res.proposal.timeframe.end) ?? Calendar.current.date(byAdding: .day, value: 7, to: Date())!
        } catch {
            refineError = error.localizedDescription
        }
    }

    @ViewBuilder
    private func proposalEditor(proposal: RefineResponse.Proposal, alternatives: [RefineResponse.Alternative]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Proposed").font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                TextField("Refined goal", text: $selectedGoal)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    DatePicker("Start", selection: $selectedStart, displayedComponents: [.date])
                    DatePicker("End", selection: $selectedEnd, displayedComponents: [.date])
                }
                Text("Why: \(proposal.whyTheseDates)").font(.footnote).foregroundStyle(.secondary)
            }
            .padding(12)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            if !alternatives.isEmpty {
                Text("Alternatives").font(.subheadline)
                ForEach(Array(alternatives.enumerated()), id: \.offset) { _, alt in
                    Button {
                        selectedGoal = alt.refinedGoal
                        selectedStart = parseYYYYMMDD(alt.timeframe.start) ?? selectedStart
                        selectedEnd   = parseYYYYMMDD(alt.timeframe.end)   ?? selectedEnd
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(alt.refinedGoal).font(.body)
                            Text("\(alt.timeframe.start) → \(alt.timeframe.end)")
                                .font(.caption).foregroundStyle(.secondary)
                            Text(alt.whyTheseDates)
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
    }

    private var refinePlanSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Generate plan").font(.headline)
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    Task { await doPlan(goal: selectedGoal, start: selectedStart, end: selectedEnd) }
                } label: {
                    if planLoading { ProgressView() } else { Text("Create Plan") }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedGoal.trimmingCharacters(in: .whitespaces).isEmpty || planLoading)

                if let err = planError {
                    Text(err).font(.footnote).foregroundStyle(.red).textSelection(.enabled)
                }
            }
            Text("You’ll review milestones and save them to your “Scoreline” reminders list before anything is written.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    // MARK: - DIRECT FLOW

    private var directPlanSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Plan directly").font(.headline)

            TextField("Goal", text: $directGoal)
                .textFieldStyle(.roundedBorder)
                .focused($directGoalFocused)

            VStack {
                DatePicker("Start", selection: $directStart, displayedComponents: [.date])
                DatePicker("End", selection: $directEnd, displayedComponents: [.date])
            }

            Button {
                directGoalFocused = false
                Task { await doPlan(goal: directGoal, start: directStart, end: directEnd) }
            } label: {
                if planLoading { ProgressView() } else { Text("Create Plan") }
            }
            .buttonStyle(.borderedProminent)
            .disabled(directGoal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || planLoading)

            if let err = planError {
                Text(err).font(.footnote).foregroundStyle(.red).textSelection(.enabled)
            }

            Text("You’ll review milestones and save them to your “Scoreline” reminders list before anything is written.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    // MARK: - Plan call (shared)

    private func doPlan(goal: String, start: Date, end: Date) async {
        planLoading = true
        planStreaming = true
        planPct = 0
        planNote = ""
        planError = nil
        defer {
            planLoading = false
            planStreaming = false
        }
        do {
            let tf = PlanRequest.Timeframe(
                start: PlanningDate.yyyyMMdd(from: start),
                end: PlanningDate.yyyyMMdd(from: end)
            )
            let req = PlanRequest(goal: goal, timeframe: tf, userSteps: nil)

            // Use streaming version so we can update a progress bar.
            let plan = try await APIClient.shared.planStream(input: req) { pct, note in
                Task { @MainActor in
                    self.planPct = min(max(pct, 0), 100)
                    self.planNote = note
                }
            }
            planToReview = plan
        } catch {
            planError = error.localizedDescription
        }
    }

    // MARK: - Helpers

    private func parseYYYYMMDD(_ s: String) -> Date? {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(identifier: "America/New_York")
        df.dateFormat = "yyyy-MM-dd"
        return df.date(from: s)
    }
}
