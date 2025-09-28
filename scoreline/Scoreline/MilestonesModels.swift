//
//  MilestonesModels.swift
//  Scoreline
//
//  Created by Mehul Jasti on 9/28/25.
//

import Foundation

// MARK: - /api/me

public struct MeDTO: Codable {
    public let appleSub: String
    public let name: String?
    public let email: String?
    public let totalPoints: Int

    enum CodingKeys: String, CodingKey {
        case appleSub = "appleSub"
        case name, email
        case totalPoints = "totalPoints"
    }
}

// MARK: - Plans returned from backend

public struct PlanDTO: Codable {
    public let id: Int
    public let appleSub: String
    public let goal: String
    public let timeframeStart: String?
    public let timeframeEnd: String?
    public let smartSpecific: String?
    public let smartMeasurable: String?
    public let smartAchievable: String?
    public let smartRelevant: String?
    public let smartTimeBound: String?
    public let isActive: Bool
    public let createdAt: String
    public let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case appleSub = "appleSub"
        case goal
        case timeframeStart = "timeframeStart"
        case timeframeEnd = "timeframeEnd"
        case smartSpecific = "smartSpecific"
        case smartMeasurable = "smartMeasurable"
        case smartAchievable = "smartAchievable"
        case smartRelevant = "smartRelevant"
        case smartTimeBound = "smartTimeBound"
        case isActive = "isActive"
        case createdAt = "createdAt"
        case updatedAt = "updatedAt"
    }
}

// MARK: - Milestones returned from backend

public struct MilestoneDTO: Codable, Equatable {
    public let id: Int
    public let appleSub: String
    public let planId: Int
    public let stableKey: String
    public let title: String
    public let notes: String?
    public let dueTs: String?
    public let importancePoints: Int
    public let isCompleted: Bool
    public let completedAt: String?
    public let completedSource: String?
    public let reminderIdentifier: String?
    public let reminderExternalIdentifier: String?
    public let lastSyncedAt: String?
    public let createdAt: String
    public let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case appleSub = "appleSub"
        case planId = "planId"
        case stableKey = "stableKey"
        case title
        case notes
        case dueTs = "dueTs"
        case importancePoints = "importancePoints"
        case isCompleted = "isCompleted"
        case completedAt = "completedAt"
        case completedSource = "completedSource"
        case reminderIdentifier = "reminderIdentifier"
        case reminderExternalIdentifier = "reminderExternalIdentifier"
        case lastSyncedAt = "lastSyncedAt"
        case createdAt = "createdAt"
        case updatedAt = "updatedAt"
    }
}

// MARK: - POST /api/milestones (request)

/// Body to create a new plan + milestones.
public struct PostMilestonesBody: Codable {
    public struct Plan: Codable {
        public let goal: String
        public let timeframeStart: String?      // yyyy-MM-dd
        public let timeframeEnd: String?        // yyyy-MM-dd
        public let smartSpecific: String?
        public let smartMeasurable: String?
        public let smartAchievable: String?
        public let smartRelevant: String?
        public let smartTimeBound: String?

        public init(
            goal: String,
            timeframeStart: String?,
            timeframeEnd: String?,
            smartSpecific: String?,
            smartMeasurable: String?,
            smartAchievable: String?,
            smartRelevant: String?,
            smartTimeBound: String?
        ) {
            self.goal = goal
            self.timeframeStart = timeframeStart
            self.timeframeEnd = timeframeEnd
            self.smartSpecific = smartSpecific
            self.smartMeasurable = smartMeasurable
            self.smartAchievable = smartAchievable
            self.smartRelevant = smartRelevant
            self.smartTimeBound = smartTimeBound
        }
    }

    public struct Milestone: Codable {
        public let stableKey: String
        public let title: String
        public let notes: String?
        public let due: String?                 // ISO8601 or yyyy-MM-dd
        public let importancePoints: Int
        public let isCompleted: Bool
        public let reminderIdentifier: String?
        public let reminderExternalIdentifier: String?

        public init(
            stableKey: String,
            title: String,
            notes: String?,
            due: String?,
            importancePoints: Int,
            isCompleted: Bool,
            reminderIdentifier: String?,
            reminderExternalIdentifier: String?
        ) {
            self.stableKey = stableKey
            self.title = title
            self.notes = notes
            self.due = due
            self.importancePoints = importancePoints
            self.isCompleted = isCompleted
            self.reminderIdentifier = reminderIdentifier
            self.reminderExternalIdentifier = reminderExternalIdentifier
        }
    }

    public let plan: Plan
    public let milestones: [Milestone]
    /// If true, server will scale importance points so they sum to 1000.
    public let normalizeImportance: Bool
    /// If true, mark this plan as active.
    public let activatePlan: Bool

    public init(plan: Plan, milestones: [Milestone], normalizeImportance: Bool = true, activatePlan: Bool = true) {
        self.plan = plan
        self.milestones = milestones
        self.normalizeImportance = normalizeImportance
        self.activatePlan = activatePlan
    }
}

// MARK: - POST /api/milestones (response)

public struct PostMilestonesResponse: Codable {
    public let ok: Bool
    public let plan: PlanDTO
    public let milestones: [MilestoneDTO]
    public let pointsAwarded: Int?
    public let totalPoints: Int?
}

// MARK: - PATCH /api/milestones/[id] (request)

/// Double-optional for text fields (omit/null/value) so PATCH can clear fields.
/// - `nil`          => omit field
/// - `.some(nil)`   => set field to null
/// - `.some(value)` => set field to value
public struct PatchMilestoneBody: Codable {
    public var title: String?
    public var notes: String??
    public var due: String??
    public var importancePoints: Int?
    public var isCompleted: Bool?
    public var completedAt: String??
    public var reminderIdentifier: String??
    public var reminderExternalIdentifier: String??

    public init(
        title: String? = nil,
        notes: String?? = nil,
        due: String?? = nil,
        importancePoints: Int? = nil,
        isCompleted: Bool? = nil,
        completedAt: String?? = nil,
        reminderIdentifier: String?? = nil,
        reminderExternalIdentifier: String?? = nil
    ) {
        self.title = title
        self.notes = notes
        self.due = due
        self.importancePoints = importancePoints
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.reminderIdentifier = reminderIdentifier
        self.reminderExternalIdentifier = reminderExternalIdentifier
    }
}

// MARK: - PATCH /api/milestones/[id] (response)

public struct MilestonePatchResult: Codable {
    public let ok: Bool
    public let milestone: MilestoneDTO
    public let totalPoints: Int?
}

// MARK: - POST /api/milestones/sync (request)

public struct SyncDelta: Codable {
    public let stableKey: String
    public let isCompleted: Bool
    public let completedAt: String?
    public let reminderIdentifier: String?
    public let reminderExternalIdentifier: String?

    public init(
        stableKey: String,
        isCompleted: Bool,
        completedAt: String?,
        reminderIdentifier: String?,
        reminderExternalIdentifier: String?
    ) {
        self.stableKey = stableKey
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.reminderIdentifier = reminderIdentifier
        self.reminderExternalIdentifier = reminderExternalIdentifier
    }
}

// MARK: - POST /api/milestones/sync (response)

public struct SyncResponse: Codable {
    public let ok: Bool
    public let updated: [MilestoneDTO]
    public let totalPoints: Int?
}

