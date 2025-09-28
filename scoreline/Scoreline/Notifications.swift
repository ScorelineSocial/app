//
//  Notifications.swift
//  Scoreline
//
//  Created by Mehul Jasti on 9/28/25.
//

import Foundation

extension Notification.Name {
    /// Fire this when a plan is created/activated/deactivated.
    static let planStateChanged = Notification.Name("PlanStateChanged")
    /// Fire this after milestones sync completes (local sync finished).
    static let milestonesSynced = Notification.Name("MilestonesSynced")
}
