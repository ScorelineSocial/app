//
//  MilestonesSyncManager.swift
//  Scoreline
//
//  Created by Mehul Jasti on 9/28/25.
//

import Foundation

/// Coalesces foreground syncs and throttles them a bit to avoid spamming the server.
actor MilestonesSyncManager {
    static let shared = MilestonesSyncManager()

    private var lastAttemptAt: Date?
    private var inFlight: Task<Void, Never>?
    private let throttleSeconds: TimeInterval = 60 // don't sync more than once per minute

    /// Call this on app foreground (or wherever apprYesopriate). It will coalesce/throttle.
    func syncOnForeground() {
        // Throttle
        if let last = lastAttemptAt, Date().timeIntervalSince(last) < throttleSeconds {
            return
        }
        lastAttemptAt = Date()

        // Coalesce
        if let existing = inFlight {
            _ = existing // already running
            return
        }

        let task = Task { [weak self] in
            defer { Task { await self?.clearInFlight() } }
            await self?.runSync()
        }
        inFlight = task
    }

    private func clearInFlight() {
        inFlight = nil
    }

    /// Performs the actual sync:
    ///  - Reads local Reminders completion states (includes identifiers and completion date)
    ///  - Sends deltas to `/api/milestones/sync`
    ///  - Posts `.milestonesSynced` notification on completion (success or graceful no-op)
    private func runSync() async {
        do {
            // 1) Collect completion deltas from the Scoreline list
            let deltas = try await RemindersService.shared.collectCompletionDeltas(listName: "Scoreline")
            if deltas.isEmpty {
                // Nothing to push; still notify so UI can refresh if listening.
                await notifySynced()
                return
            }

            // 2) Send to backend (APIClient.syncMilestones is @MainActor)
            let _ = try await MainActor.run {
                Task { try await APIClient.shared.syncMilestones(deltas) }
            }.value

            // 3) Notify UI
            await notifySynced()
        } catch {
            // Soft-fail: do not throw; just log in DEBUG and end.
            #if DEBUG
            print("⚠️ MilestonesSyncManager.runSync() error: \(error.localizedDescription)")
            #endif
            await notifySynced()
        }
    }

    @MainActor
    private func notifySynced() {
        NotificationCenter.default.post(name: .milestonesSynced, object: nil)
    }
}
