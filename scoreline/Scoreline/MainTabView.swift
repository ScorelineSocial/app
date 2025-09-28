//
//  MainTabView.swift
//  Scoreline
//
//  Created by Mehul Jasti on 9/27/25.
//

import SwiftUI
import Combine

@MainActor
final class GrindCalendarViewModel: ObservableObject {
    @Published var plan: PlanDTO?
    @Published var allMilestones: [MilestoneDTO] = []
    @Published var loading: Bool = true
    @Published var error: String?

    private var didLoadOnce = false

    func loadIfNeeded() async {
        guard !didLoadOnce else { return }
        await load()
        didLoadOnce = true
    }

    func reload() async { await load() }

    // Single-item convenience (kept for callers)
    func applyMilestoneOptimistic(_ updated: MilestoneDTO) {
        applyMilestonesOptimistic([updated])
    }

    // Bulk optimistic merge (order-preserving). Replaces in-place when IDs match.
    // NOTE: No Equatable conformance required; we simply replace when an ID matches.
    func applyMilestonesOptimistic(_ updates: [MilestoneDTO]) {
        guard !updates.isEmpty, !allMilestones.isEmpty else { return }

        let byID: [Int: MilestoneDTO] = Dictionary(uniqueKeysWithValues: updates.map { ($0.id, $0) })

        var changed = false
        var newArray = allMilestones
        for idx in newArray.indices {
            let old = newArray[idx]
            if let candidate = byID[old.id] {
                // Replace unconditionally to avoid needing Equatable; cheap and safe.
                if old.id != candidate.id
                    || old.updatedAt != candidate.updatedAt
                    || old.isCompleted != candidate.isCompleted
                    || old.importancePoints != candidate.importancePoints
                    || old.title != candidate.title
                    || old.dueTs != candidate.dueTs
                    || old.notes != candidate.notes
                {
                    newArray[idx] = candidate
                    changed = true
                }
            }
        }
        if changed { allMilestones = newArray }
    }

    // Fetch plan + all milestones
    func load() async {
        loading = true
        error = nil
        do {
            let (p, ms) = try await APIClient.shared.getActivePlanWithMilestones(status: .all)
            plan = p
            allMilestones = ms
            loading = false
        } catch {
            self.error = error.localizedDescription
            self.loading = false
        }
    }
}

// MARK: - RootMode
private enum RootMode { case home, milestones }

struct MainTabView: View {
    let user: User

    @State private var mode: RootMode? = nil
    @State private var loading = true
    @State private var error: String?

    /// 0 = Home/Grind, 1 = Focus
    @State private var selectedTab: Int = 0

    @StateObject private var calendarVM = GrindCalendarViewModel()

    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                Group {
                    if loading {
                        Color.clear
                    } else if mode == .milestones {
                        GrindCalendarView(vm: calendarVM)
                    } else {
                        HomeView(user: user)
                    }
                }
                .tag(0)
                .tabItem {
                    Label(mode == .milestones ? "Grind" : "Home",
                          systemImage: mode == .milestones ? "map" : "house.fill")
                }

                GrindPomodoroView()
                    .tag(1)
                    .tabItem { Label("Focus", systemImage: "timer") }
            }

            if loading {
                VStack(spacing: 12) {
                    ProgressView()
                        .progressViewStyle(
                            CircularProgressViewStyle(
                                tint: Color(.sRGB, red: 167/255, green: 139/255, blue: 250/255, opacity: 1)
                            )
                        )
                    Text("Checking your plans…")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.ultraThinMaterial)
                .edgesIgnoringSafeArea(.all)
            } else if let err = error {
                VStack(spacing: 12) {
                    VStack(spacing: 6) {
                        Text("Unable to determine plan state").font(.headline)
                        Text(err)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    HStack(spacing: 12) {
                        Button("Retry") { Task { await reloadMode() } }
                            .buttonStyle(.borderedProminent)
                        Button("Dismiss") { error = nil }
                            .buttonStyle(.bordered)
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemBackground).opacity(0.95))
                )
                .shadow(radius: 12)
                .padding()
            }
        }
        .task {
            await reloadMode()
            await calendarVM.loadIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("MilestonesSynced"))) { _ in
            Task {
                await reloadMode(preserveUX: true)
                if mode == .milestones { await calendarVM.reload() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("PlanStateChanged"))) { _ in
            Task {
                await reloadMode(preserveUX: true)
                if mode == .milestones { await calendarVM.reload() }
            }
        }
    }
}

// MARK: - Data
private extension MainTabView {
    /// Fix: when multiple active plans exist, `plan` will be nil but milestones are present.
    /// Enter `.milestones` mode if there's *either* a single plan OR any milestones at all.
    func reloadMode(preserveUX: Bool = false) async {
        if !preserveUX {
            loading = true
            error = nil
        }
        do {
            // IMPORTANT: ask for open milestones for active plans
            let (plan, milestones) = try await APIClient.shared.getActivePlanWithMilestones(status: .open)

            let hasAnythingToShow = (plan != nil) || (!milestones.isEmpty)
            let newMode: RootMode = hasAnythingToShow ? .milestones : .home

            if preserveUX {
                mode = newMode
            } else {
                mode = newMode
                selectedTab = 0
            }
            loading = false
            error = nil
        } catch {
            self.error = error.localizedDescription
            self.loading = false
        }
    }
}
