//
//  GrindCalendarView.swift
//  Scoreline
//
//  Created by Mehul Jasti on 9/29/25.
//

import SwiftUI

struct GrindCalendarView: View {
    // View model is provided by MainTabView (kept alive via @StateObject there)
    @ObservedObject var vm: GrindCalendarViewModel

    // Local UI state
    @State private var showingProfile: Bool = false
    @State private var showingGoals: Bool = false
    @State private var monthAnchor: Date = Date()

    private struct SheetDate: Identifiable {
        let date: Date
        var id: String { ISO8601DateFormatter().string(from: date) }
    }
    @State private var selectedDate: SheetDate?

    private let calendar = Calendar.current

    // Overall progress (computed over ALL milestones)
    private var totalStones: Int {
        vm.allMilestones.reduce(0) { $0 + $1.importancePoints }
    }
    private var completedStones: Int {
        vm.allMilestones.filter { $0.isCompleted }.reduce(0) { $0 + $1.importancePoints }
    }
    private var progressLabel: String {
        let pct = totalStones > 0 ? Int(round(Double(completedStones) / Double(totalStones) * 100)) : 0
        return "\(completedStones)/\(max(totalStones, 0)) stones (\(pct)%)"
    }

    var body: some View {
        NavigationStack {
            Group {
                if vm.loading {
                    VStack(spacing: 10) {
                        ProgressView().tint(Palette.amethyst)
                        Text("Loading…").font(.footnote).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let err = vm.error {
                    VStack(spacing: 10) {
                        Text("Something went wrong").font(.headline)
                        Text(err).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Button("Retry") { Task { await vm.reload() } }
                            .buttonStyle(.borderedProminent)
                            .tint(Palette.amethyst)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            headerCard
                            monthHeader
                            weekdayHeader
                            monthGrid
                                .padding(.horizontal, 2)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                    }
                }
            }
            .navigationTitle("Grindstone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button {
                        showingGoals = true
                    } label: {
                        Image("Goals")
//                            .renderingMode(.template)   // allow .tint to work
                            .resizable()                // opt into resizing
                            .scaledToFit()              // keep aspect ratio
                            .frame(width: 35, height: 50) // <= keep it small like an SF Symbol
                            .padding(6)
//                            .background(Capsule().fill(Palette.badgeLavender))
                            .contentShape(Rectangle())
                    }
                    .tint(Palette.amethyst)
                    .accessibilityLabel("Goals")
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showingProfile = true
                    } label: {
                        Image(systemName: "person.crop.circle")
                            .imageScale(.large)
                    }
                    .accessibilityLabel("Profile")
                }
            }

            // Profile as full screen (tabs hidden)
            .fullScreenCover(isPresented: $showingProfile) {
                NavigationStack {
                    ProfileView()
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button("Close") { showingProfile = false }
                            }
                        }
                }
            }
            .background(
                LinearGradient(
                    colors: [Palette.bgTop, Palette.bgBottom],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            )
        }
        // Day detail sheet
        .sheet(item: $selectedDate) { sheet in
            DayDetailSheet(
                date: sheet.date,
                milestones: milestones(on: sheet.date),
                onToggle: { m, newValue in
                    Task { await toggle(m, to: newValue) }
                }
            )
            .presentationDetents([.medium, .large])
        }
        // in GrindCalendarView toolbar .sheet where you present the goals UI:
        .sheet(isPresented: $showingGoals) {
            NavigationStack {
                GoalsView(vm: vm) // pass your existing VM, no User needed
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Close") { showingGoals = false }
                        }
                    }
                    .background(
                        LinearGradient(
                            colors: [Palette.bgTop, Palette.bgBottom],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .ignoresSafeArea()
                    )
            }
        }
    }
}

// MARK: - Header (Goal + progress)
private extension GrindCalendarView {
    @ViewBuilder
    var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            // If a single plan is selected/exposed on the VM, show it; otherwise show a generic label.
            if let single = vm.plan {
                Text(single.goal.isEmpty ? "Your quest" : single.goal)
                    .font(.headline)
                    .foregroundStyle(Palette.ink)
                if let s = single.timeframeStart, let e = single.timeframeEnd, !s.isEmpty, !e.isEmpty {
                    Text("\(s) → \(e)")
                        .font(.caption)
                        .foregroundStyle(Palette.inkSecondary)
                }
            } else {
                Text("Your goals")
                    .font(.headline)
                    .foregroundStyle(Palette.ink)
                Text("Calendar aggregates milestones across all active goals.")
                    .font(.caption)
                    .foregroundStyle(Palette.inkSecondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: Double(completedStones), total: Double(max(totalStones, 1)))
                    .progressViewStyle(.linear)
                    .tint(Palette.amethyst)
                Text(progressLabel)
                    .font(.caption2)
                    .foregroundStyle(Palette.inkTertiary)
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

// MARK: - Month chrome
private extension GrindCalendarView {
    @ViewBuilder
    var monthHeader: some View {
        HStack {
            RoundIconButton(systemName: "chevron.left") {
                withAnimation(.easeInOut) { monthAnchor = addMonths(-1, to: monthAnchor) }
            }

            Spacer()

            Text(monthTitle(for: monthAnchor))
                .font(.headline)
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(Palette.badgeLavender))

            Spacer()

            RoundIconButton(systemName: "chevron.right") {
                withAnimation(.easeInOut) { monthAnchor = addMonths(1, to: monthAnchor) }
            }
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    var weekdayHeader: some View {
        let symbols = calendar.shortWeekdaySymbols
        let startIndex = calendar.firstWeekday - 1
        let ordered = Array(symbols[startIndex...] + symbols[..<startIndex])
        HStack(spacing: 6) {
            ForEach(ordered, id: \.self) { s in
                Text(s.uppercased())
                    .font(.caption2).bold()
                    .foregroundStyle(Palette.inkTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Palette.strip)
                    )
            }
        }
        .padding(.bottom, 4)
    }
}

// MARK: - Month grid
private extension GrindCalendarView {
    @ViewBuilder
    var monthGrid: some View {
        let days = makeMonthDays(for: monthAnchor)
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 8) {
            ForEach(days) { day in
                DayCellView(
                    day: day,
                    chips: chips(for: day.date),
                    onTapDay: { tappedDate in
                        selectedDate = SheetDate(date: tappedDate)
                    }
                )
            }
        }
    }

    func chips(for date: Date) -> [MilestoneChipModel] {
        let items = milestones(on: date)
        let today = calendar.startOfDay(for: Date())

        return items.prefix(3).map { m in
            let dueDate = date
            let isOverdue = !m.isCompleted && dueDate < today
            let tint: Color = m.isCompleted ? Palette.chipMint
                            : (isOverdue ? Palette.chipRose : Palette.chipSky)
            return MilestoneChipModel(id: m.id, title: m.title, coins: m.importancePoints, isCompleted: m.isCompleted, tint: tint)
        }
    }

    func milestones(on date: Date) -> [MilestoneDTO] {
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        return vm.allMilestones
            .filter { m in
                guard let iso = m.dueTs, let d = PlanningDate.date(fromISO: iso) else { return false }
                return d >= start && d < end
            }
            .sorted { ($0.importancePoints, $0.title) > ($1.importancePoints, $1.title) }
    }
}

// MARK: - Data mutations
private extension GrindCalendarView {
    func toggle(_ m: MilestoneDTO, to newValue: Bool) async {
        guard let idx = vm.allMilestones.firstIndex(where: { $0.id == m.id }) else { return }
        let isoNow = PlanningDate.iso8601Z.string(from: Date())

        // optimistic
        let original = vm.allMilestones[idx]
        let optimistic = updated(original, isCompleted: newValue, completedAtISO: newValue ? isoNow : nil)
        await MainActor.run {
            vm.applyMilestoneOptimistic(optimistic)
        }

        do {
            let body = PatchMilestoneBody(
                isCompleted: newValue,
                completedAt: newValue ? .some(isoNow) : .some(nil)
            )
            _ = try await APIClient.shared.patchMilestone(id: m.id, body: body)
        } catch {
            // rollback
            await MainActor.run {
                vm.applyMilestoneOptimistic(original)
            }
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
}

// MARK: - Day models & helpers
private struct MonthDay: Identifiable {
    let id: String
    let date: Date
    let isCurrentMonth: Bool
    let isToday: Bool
}

private extension GrindCalendarView {
    func monthTitle(for anchor: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "LLLL yyyy"
        return df.string(from: anchor)
    }

    func startOfMonth(_ date: Date) -> Date {
        let comps = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: comps) ?? date
    }

    func addMonths(_ delta: Int, to date: Date) -> Date {
        calendar.date(byAdding: .month, value: delta, to: date) ?? date
    }

    func makeMonthDays(for anchor: Date) -> [MonthDay] {
        let firstOfMonth = startOfMonth(anchor)
        let firstWeekday = calendar.component(.weekday, from: firstOfMonth)
        let shift = (firstWeekday - calendar.firstWeekday + 7) % 7
        let gridStart = calendar.date(byAdding: .day, value: -shift, to: firstOfMonth) ?? firstOfMonth

        var days: [MonthDay] = []
        let today = calendar.startOfDay(for: Date())
        for offset in 0..<42 {
            guard let d = calendar.date(byAdding: .day, value: offset, to: gridStart) else { continue }
            let isCurrent = calendar.isDate(d, equalTo: firstOfMonth, toGranularity: .month)
            let isToday = calendar.isDate(d, inSameDayAs: today)
            let id = ISO8601DateFormatter().string(from: d)
            days.append(MonthDay(id: id, date: d, isCurrentMonth: isCurrent, isToday: isToday))
        }
        return days
    }
}

// MARK: - Day cell view & chip
private struct MilestoneChipModel: Identifiable {
    let id: Int
    let title: String
    let coins: Int
    let isCompleted: Bool
    let tint: Color
}

private struct DayCellView: View {
    let day: MonthDay
    let chips: [MilestoneChipModel]
    let onTapDay: (Date) -> Void

    var body: some View {
        Button {
            onTapDay(day.date)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(dayNumber(day.date))
                        .font(.caption).bold()
                        .foregroundStyle(day.isCurrentMonth ? Palette.ink : Palette.inkTertiary)
                    if day.isToday {
                        Circle().frame(width: 6, height: 6)
                            .foregroundStyle(Palette.amethyst)
                    }
                    Spacer(minLength: 0)
                }

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(chips.prefix(2)) { c in
                        HStack(spacing: 6) {
                            Image(systemName: c.isCompleted ? "checkmark.circle.fill" : "circle")
                                .imageScale(.small)
                                .foregroundStyle(Palette.ink)
                            Text(c.title)
                                .font(.caption2)
                                .foregroundStyle(Palette.ink)
                                .lineLimit(1)
                            Spacer()
                            Text("\(c.coins)")
                                .font(.caption2).monospacedDigit()
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Palette.coinBadge)
                                .clipShape(Capsule())
                        }
                        .padding(.horizontal, 6).padding(.vertical, 4)
                        .background(c.tint)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    if chips.count > 2 {
                        Text("+\(chips.count - 2) more")
                            .font(.caption2)
                            .foregroundStyle(Palette.inkTertiary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .frame(minHeight: 78)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(day.isCurrentMonth ? Palette.dayCard : Palette.dayCard.opacity(0.7))
                    .shadow(color: Palette.shadow.opacity(day.isToday ? 0.25 : 0.12), radius: day.isToday ? 6 : 4, x: 0, y: 1)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(day.isToday ? Palette.amethyst.opacity(0.6) : Color.clear, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func dayNumber(_ date: Date) -> String {
        let d = Calendar.current.component(.day, from: date)
        return "\(d)"
    }
}

// MARK: - Day detail sheet
private struct DayDetailSheet: View, Identifiable {
    var id: String { ISO8601DateFormatter().string(from: date) }

    let date: Date
    let milestones: [MilestoneDTO]
    let onToggle: (MilestoneDTO, Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(headerDate(date))
                .font(.headline)
                .foregroundStyle(Palette.ink)

            if milestones.isEmpty {
                Text("No milestones on this day.")
                    .foregroundStyle(Palette.inkTertiary)
            } else {
                List(milestones, id: \.id) { m in
                    Button {
                        onToggle(m, !m.isCompleted)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: m.isCompleted ? "checkmark.circle.fill" : "circle")
                                .imageScale(.large)
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(Palette.ink)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(m.title).font(.body).foregroundStyle(Palette.ink)
                                HStack {
                                    Text("\(m.importancePoints) stones")
                                        .font(.caption).foregroundStyle(Palette.inkTertiary)
                                    if let iso = m.dueTs, let d = PlanningDate.date(fromISO: iso) {
                                        Text("• \(Formatter.eventDateTime.string(from: d))")
                                            .font(.caption).foregroundStyle(Palette.inkTertiary)
                                    }
                                }
                            }
                            Spacer()
                        }
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Palette.sheetBg)
            }
        }
        .padding(.top, 24)
        .padding(.horizontal, 16)
        .background(Palette.sheetBg)
    }

    private func headerDate(_ d: Date) -> String {
        let df = DateFormatter()
        df.dateStyle = .full
        df.timeStyle = .none
        return df.string(from: d)
    }
}

// MARK: - Controls

private struct RoundIconButton: View {
    let systemName: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .imageScale(.medium)
                .padding(8)
                .background(Circle().fill(Palette.badgeLavender))
        }
        .tint(Palette.amethyst)
    }
}
