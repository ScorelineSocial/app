//
//  PermissionsManager.swift
//  Scoreline
//
//  Created by Mehul Jasti on 9/27/25.
//


import Foundation
import EventKit
import Combine

@MainActor
final class PermissionsManager: ObservableObject {
    @Published var calendarAuthorized = false
    @Published var remindersAuthorized = false

    private let store = EKEventStore()

    init() {
        refreshStatuses()
    }

    func refreshStatuses() {
        calendarAuthorized = Self.isAuthorized(for: .event)
        remindersAuthorized = Self.isAuthorized(for: .reminder)
    }

    /// Treat both full and write-only as "authorized". If you only want full access, remove `.writeOnly`.
    static func isAuthorized(for entity: EKEntityType) -> Bool {
        switch EKEventStore.authorizationStatus(for: entity) {
        case .fullAccess, .writeOnly:
            return true
        default:
            return false
        }
    }

    func requestCalendarAccess() async {
        do {
            // Returns a Bool in iOS 17+
            let granted = try await store.requestFullAccessToEvents()
            calendarAuthorized = granted
        } catch {
            calendarAuthorized = false
        }
    }

    func requestRemindersAccess() async {
        do {
            // Returns a Bool in iOS 17+
            let granted = try await store.requestFullAccessToReminders()
            remindersAuthorized = granted
        } catch {
            remindersAuthorized = false
        }
    }
}
