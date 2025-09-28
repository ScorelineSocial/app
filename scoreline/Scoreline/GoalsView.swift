//
//  GoalsView.swift
//  Scoreline
//
//  Created by Mehul Jasti on 9/28/25.
//

import SwiftUI

/// Goals dashboard with a right-side tab rail:
/// - Master tab shows all goals, year bars, and quick-complete actions
/// - Each goal gets its own tab with a detailed list
/// Also lets you create **another goal** via a top-right "+" that opens a sheet.
struct GoalsView: View {
    // Reuse the same VM as the calendar so data stays in sync.
    @ObservedObject var vm: GrindCalendarViewModel
    @Environment(SessionViewModel.self) private var session

    // Tabs: first tab is master, then one per goal (planId)
    @State private var selectedTab: Tab = .master

    // New-goal creation
    @State private var showingNewGoalSheet = false
    @State private var planToReview: PlanResponse?

    // Colors for goals (deterministic by planId)
    private let goalColors: [Color] = [
        Color(.sRGB, red: 167/255, green: 139/255, blue: 250/255, opacity: 1), // amethyst
        Color(.sRGB, red: 189/255, green: 219/255, blue: 255/255, opacity: 1), // sky
        Color(.sRGB, red: 197/255, green: 243/255, blue: 220/255, opacity: 1), // mint
        Color(.sRGB, red: 255/255, green: 214/255, blue: 222/255, opacity: 1), // rose
        Color(.sRGB, red: 253/255, green: 224/255, blue: 130/255, opacity: 1), // gold
        Color(.sRGB, red: 237/255, green: 233/255, blue: 254/255, opacity: 1), // lavender
    ]

    var body: some View {
        HStack(spacing: 0) {
            // CONTENT
            Group {
                switch selectedTab {
                case .master:
                    MasterGoalsView(
                        goals: goalsOverview(),
                        colorFor: color(for:)
                    ) { planId in
                        selectedTab = .goal(planId)
                    } onToggle: { m, newValue in
                        Task { await toggle(m, to: newValue) }
                    }

                case .goal(let planId):
                    if let goal = goalDetail(for: planId) {
                        GoalDetailView(
                            goal: goal,
                            color: color(for: planId)
                        ) { m, newValue in
                            Task { await toggle(m, to: newValue) }
                        }
                    } else {
                        MissingGoalView()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                LinearGradient(
                    colors: [Palette.bgTop, Palette.bgBottom],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ).ignoresSafeArea()
            )

            // RIGHT TAB RAIL
            RightTabRail(
                tabs: tabs(),
                selected: selectedTab,
                colorFor: color(for:),
                onSelect: { selectedTab = $0 }
            )
            .frame(width: 72)
            .background(Palette.dayCard)
        }
        .navigationTitle("Goals")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingNewGoalSheet = true
                } label: {
                    Image(systemName: "plus")
                        .imageScale(.large)
                        .padding(6)
                        .background(Capsule().fill(Palette.badgeLavender))
                }
                .tint(Palette.amethyst)
                .accessibilityLabel("New Goal")
            }
        }
        // New Goal sheet
        .sheet(isPresented: $showingNewGoalSheet) {
            NewGoalSheet { plan in
                // navigate to review after generation
                planToReview = plan
                showingNewGoalSheet = false
            }
        }
        // Navigate to Review (inject user via session at nav-time)
        .navigationDestination(item: $planToReview) { plan in
            PlanReviewDestination(plan: plan)
        }
    }
}

// MARK: - Tab Model

private enum Tab: Hashable {
    case master
    case goal(Int) // planId
}

// MARK: - Data shaping

private extension GoalsView {
    struct GoalOverview: Identifiable {
        let id: Int           // planId
        let title: String
        let timeframeStart: String?
        let timeframeEnd: String?
        let total: Int
        let completed: Int
        let remaining: Int
        let milestones: [MilestoneDTO]
    }

    func tabs() -> [Tab] {
        var t: [Tab] = [.master]
        let planIds = Set(vm.allMilestones.map { $0.planId })
            .sorted()
        t.append(contentsOf: planIds.map { .goal($0) })
        return t
    }

    func goalsOverview() -> [GoalOverview] {
        let grouped = Dictionary(grouping: vm.allMilestones, by: { $0.planId })
        return grouped.keys.sorted().map { pid in
            let ms = grouped[pid] ?? []
            let total = ms.reduce(0) { $0 + $1.importancePoints }
            let completed = ms.filter { $0.isCompleted }.reduce(0) { $0 + $1.importancePoints }
            let remaining = max(0, total - completed)

            // If VM exposes only a single plan meta, use it when matching id; otherwise fallback.
            let title: String
            let tfStart: String?
            let tfEnd: String?

            if let p = vm.plan, p.id == pid {
                title = p.goal
                tfStart = p.timeframeStart
                tfEnd = p.timeframeEnd
            } else {
                // TODO: if you add vm.plans later, replace this with the real header
                title = "Goal \(pid)"
                tfStart = nil
                tfEnd = nil
            }

            return GoalOverview(
                id: pid,
                title: title,
                timeframeStart: tfStart,
                timeframeEnd: tfEnd,
                total: total,
                completed: completed,
                remaining: remaining,
                milestones: ms.sorted { ($0.isCompleted ? 1 : 0, -$0.importancePoints, $0.title) <
                                       ($1.isCompleted ? 1 : 0, -$1.importancePoints, $1.title) }
            )
        }
    }

    func goalDetail(for planId: Int) -> GoalOverview? {
        goalsOverview().first(where: { $0.id == planId })
    }

    func color(for planId: Int) -> Color {
        let palette = goalColors
        let idx = abs(planId.hashValue) % max(1, palette.count)
        return palette[idx]
    }
}

// MARK: - Subviews

/// Right vertical tab rail with a master tab and a tab per goal.
private struct RightTabRail: View {
    let tabs: [Tab]
    let selected: Tab
    let colorFor: (Int) -> Color
    let onSelect: (Tab) -> Void

    var body: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 8)

            ForEach(tabs, id: \.self) { tab in
                Button {
                    onSelect(tab)
                } label: {
                    switch tab {
                    case .master:
                        Image(systemName: "square.grid.2x2")
                            .imageScale(.large)
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(isSelected(tab) ? Palette.badgeLavender : .clear)
                            )

                    case .goal(let pid):
                        Circle()
                            .fill(colorFor(pid))
                            .frame(width: 22, height: 22)
                            .overlay(
                                Circle()
                                    .stroke(isSelected(tab) ? Palette.ink.opacity(0.6) : .clear, lineWidth: 2)
                            )
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(isSelected(tab) ? Palette.badgeLavender : .clear)
                            )
                    }
                }
                .buttonStyle(.plain)
                .tint(Palette.amethyst)
            }

            Spacer(minLength: 8)
        }
        .padding(.vertical, 8)
    }

    private func isSelected(_ t: Tab) -> Bool { t == selected }
}

/// Master view: list all goals with year bar + remaining and quick toggling.
private struct MasterGoalsView: View {
    let goals: [GoalsView.GoalOverview]
    let colorFor: (Int) -> Color
    let onSelectGoal: (Int) -> Void
    let onToggle: (MilestoneDTO, Bool) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ForEach(goals) { g in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(g.title)
                                .font(.headline)
                                .foregroundStyle(Palette.ink)
                            Spacer()
                            Text("\(g.remaining) / \(g.total) stones left")
                                .font(.caption).monospacedDigit()
                                .foregroundStyle(Palette.inkSecondary)
                        }

                        YearBar(
                            startISO: g.timeframeStart,
                            endISO: g.timeframeEnd,
                            color: colorFor(g.id)
                        )

                        // Top 3 remaining milestones quick actions
                        let remaining = g.milestones.filter { !$0.isCompleted }
                        if !remaining.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(remaining.prefix(3), id: \.id) { m in
                                    Button {
                                        onToggle(m, true)
                                    } label: {
                                        HStack {
                                            Image(systemName: "circle")
                                            Text(m.title).lineLimit(1)
                                            Spacer()
                                            Text("\(m.importancePoints)")
                                                .font(.caption2).monospacedDigit()
                                                .padding(.horizontal, 6).padding(.vertical, 2)
                                                .background(Palette.coinBadge)
                                                .clipShape(Capsule())
                                        }
                                        .padding(8)
                                        .background(Palette.chipSky)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        HStack {
                            Spacer()
                            Button {
                                onSelectGoal(g.id)
                            } label: {
                                Label("Open", systemImage: "chevron.left.slash.chevron.right")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(
                                LinearGradient(colors: [Palette.cardTop, Palette.cardBottom],
                                               startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                            .shadow(color: Palette.shadow, radius: 8, x: 0, y: 2)
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }
}

/// Goal detail pane: progress, full list with toggle, and a goal-only year bar.
private struct GoalDetailView: View {
    let goal: GoalsView.GoalOverview
    let color: Color
    let onToggle: (MilestoneDTO, Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(goal.title)
                    .font(.title3).bold()
                    .foregroundStyle(Palette.ink)
                Spacer()
                Text("\(goal.remaining) / \(goal.total) left")
                    .font(.footnote).monospacedDigit()
                    .foregroundStyle(Palette.inkSecondary)
            }

            ProgressView(value: Double(goal.total - goal.remaining), total: Double(max(goal.total, 1)))
                .progressViewStyle(.linear)
                .tint(color)

            YearBar(startISO: goal.timeframeStart, endISO: goal.timeframeEnd, color: color)

            List {
                ForEach(goal.milestones, id: \.id) { m in
                    Button {
                        onToggle(m, !m.isCompleted)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: m.isCompleted ? "checkmark.circle.fill" : "circle")
                                .imageScale(.large)
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(Palette.ink)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(m.title).foregroundStyle(Palette.ink)
                                HStack {
                                    Text("\(m.importancePoints) stones")
                                    if let iso = m.dueTs, let d = PlanningDate.date(fromISO: iso) {
                                        Text("• \(Formatter.eventDateTime.string(from: d))")
                                    }
                                }
                                .font(.caption).foregroundStyle(Palette.inkTertiary)
                            }

                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Palette.sheetBg)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }
}

private struct MissingGoalView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
            Text("Goal not found").font(.headline)
            Text("It may have been archived or not yet synced.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.dayCard)
    }
}

// MARK: - Year bar (shows the colored portion of the year the goal covers)

private struct YearBar: View {
    let startISO: String?
    let endISO: String?
    let color: Color

    var body: some View {
        let year = Calendar.current.component(.year, from: Date())
        let yearStart = Calendar.current.date(from: DateComponents(year: year, month: 1, day: 1))!
        let yearEnd = Calendar.current.date(from: DateComponents(year: year + 1, month: 1, day: 1))!

        let s = date(fromISO: startISO) ?? yearStart
        let e = date(fromISO: endISO) ?? yearEnd
        let clampedStart = max(s, yearStart)
        let clampedEnd = min(e, yearEnd)

        let total = yearEnd.timeIntervalSince(yearStart)
        let startFrac = CGFloat(max(0, clampedStart.timeIntervalSince(yearStart) / total))
        let endFrac = CGFloat(max(0, clampedEnd.timeIntervalSince(yearStart) / total))
        let span = max(0, endFrac - startFrac)

        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Palette.strip)
                RoundedRectangle(cornerRadius: 6)
                    .fill(color.opacity(0.85))
                    .frame(width: geo.size.width * span)
                    .offset(x: geo.size.width * startFrac)
            }
        }
        .frame(height: 12)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func date(fromISO iso: String?) -> Date? {
        guard let iso else { return nil }
        return PlanningDate.date(fromISO: iso)
    }
}

// MARK: - New Goal Sheet

private struct NewGoalSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var goal: String = ""
    @State private var start: Date = Date()
    @State private var end: Date = Calendar.current.date(byAdding: .day, value: 14, to: Date())!
    @FocusState private var goalFocused: Bool

    @State private var planLoading = false
    @State private var planStreaming = false
    @State private var planPct: Double = 0
    @State private var planNote: String = ""

    let onPlanReady: (PlanResponse) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Create a new goal") {
                    TextField("Goal", text: $goal)
                        .focused($goalFocused)

                    DatePicker("Start", selection: $start, displayedComponents: [.date])
                    DatePicker("End", selection: $end, displayedComponents: [.date])

                    Button {
                        goalFocused = false
                        Task { await createPlan() }
                    } label: {
                        if planLoading { ProgressView() } else { Text("Generate Plan") }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || planLoading)

                    if planStreaming {
                        VStack(spacing: 6) {
                            ProgressView(value: planPct, total: 100)
                                .tint(Palette.amethyst)
                            if !planNote.isEmpty {
                                Text(planNote)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Text("You can keep multiple goals active. Approve the plan to save milestones to your Scoreline list.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("New Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func createPlan() async {
        planLoading = true
        planStreaming = true
        planPct = 0
        planNote = ""
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

            let plan = try await APIClient.shared.planStream(input: req) { pct, note in
                Task { @MainActor in
                    self.planPct = min(max(pct, 0), 100)
                    self.planNote = note
                }
            }

            onPlanReady(plan)
        } catch {
            planNote = "Error: \(error.localizedDescription)"
        }
    }
}

// MARK: - Navigation wrapper that injects the user from SessionViewModel

private struct PlanReviewDestination: View, Identifiable {
    @Environment(SessionViewModel.self) private var session
    let plan: PlanResponse
    var id: String { plan.id }

    var body: some View {
        if let u = session.user {
            PlanReviewView(plan: plan, user: u)
        } else {
            VStack(spacing: 12) {
                Text("Not signed in").font(.headline)
                Text("Please sign in again to review and save this plan.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.dayCard)
            .navigationTitle("Review Plan")
        }
    }
}

// MARK: - Toggle mutation

private extension GoalsView {
    func toggle(_ m: MilestoneDTO, to newValue: Bool) async {
        guard let idx = vm.allMilestones.firstIndex(where: { $0.id == m.id }) else { return }
        let isoNow = PlanningDate.iso8601Z.string(from: Date())

        // optimistic
        let original = vm.allMilestones[idx]
        let optimistic = MilestoneDTO(
            id: m.id,
            appleSub: m.appleSub,
            planId: m.planId,
            stableKey: m.stableKey,
            title: m.title,
            notes: m.notes,
            dueTs: m.dueTs,
            importancePoints: m.importancePoints,
            isCompleted: newValue,
            completedAt: newValue ? isoNow : nil,
            completedSource: m.completedSource,
            reminderIdentifier: m.reminderIdentifier,
            reminderExternalIdentifier: m.reminderExternalIdentifier,
            lastSyncedAt: m.lastSyncedAt,
            createdAt: m.createdAt,
            updatedAt: m.updatedAt
        )
        await MainActor.run { vm.applyMilestoneOptimistic(optimistic) }

        do {
            let body = PatchMilestoneBody(
                isCompleted: newValue,
                completedAt: newValue ? .some(isoNow) : .some(nil)
            )
            _ = try await APIClient.shared.patchMilestone(id: m.id, body: body)
        } catch {
            await MainActor.run { vm.applyMilestoneOptimistic(original) }
        }
    }
}
