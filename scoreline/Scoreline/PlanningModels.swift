//
//  PlanningModels.swift
//  Scoreline
//
//  Created by Mehul Jasti on 9/27/25.
//

import Foundation

// MARK: - Refine

public struct RefineRequest: Codable {
    public struct Hints: Codable {
        public var minDays: Int?
        public var maxDays: Int?
        public var preferWeekdays: Bool?
        public var avoidWeekends: Bool?
    }

    /// Broad goal typed by the user
    public var goal: String
    /// "today" as a date string (YYYY-MM-DD) or ISO datetime
    public var today: String
    public var hints: Hints?

    public init(goal: String, today: String, hints: Hints? = nil) {
        self.goal = goal
        self.today = today
        self.hints = hints
    }
}

public struct RefineResponse: Codable {
    public struct Timeframe: Codable {
        public var start: String  // YYYY-MM-DD
        public var end: String    // YYYY-MM-DD
    }

    public struct Proposal: Codable {
        public var refinedGoal: String
        public var timeframe: Timeframe
        public var whyTheseDates: String

        enum CodingKeys: String, CodingKey {
            case refinedGoal = "refined_goal"
            case timeframe
            case whyTheseDates = "why_these_dates"
        }
    }

    public struct Alternative: Codable {
        public var refinedGoal: String
        public var timeframe: Timeframe
        public var whyTheseDates: String

        enum CodingKeys: String, CodingKey {
            case refinedGoal = "refined_goal"
            case timeframe
            case whyTheseDates = "why_these_dates"
        }
    }

    public struct InputEcho: Codable {
        public var goal: String
        public var today: String
    }

    public var status: String
    public var input: InputEcho
    public var proposal: Proposal
    public var alternatives: [Alternative]
    public var notes: [String]
}

// MARK: - Plan

public struct PlanRequest: Codable {
    public struct Timeframe: Codable {
        public var start: String   // YYYY-MM-DD or ISO
        public var end: String     // YYYY-MM-DD or ISO
    }
    public var goal: String
    public var timeframe: Timeframe
    public var userSteps: [String]?

    public init(goal: String, timeframe: Timeframe, userSteps: [String]? = nil) {
        self.goal = goal
        self.timeframe = timeframe
        self.userSteps = userSteps
    }
}

public struct PlanResponse: Codable, Identifiable, Hashable {
    // Convenience for SwiftUI lists/navigation
    public var id: String { smartGoal.statement }

    public struct ISOInterval: Codable {
        public var start: String
        public var end: String
    }

    public struct SmartGoal: Codable {
        public var statement: String
        public var specific: String
        public var measurable: String
        public var achievable: String
        public var relevant: String
        public var timeBound: String

        enum CodingKeys: String, CodingKey {
            case statement, specific, measurable, achievable, relevant
            case timeBound = "time_bound"
        }
    }

    public struct EventSummary: Codable {
        public struct Conflict: Codable, Identifiable {
            public var id: String { (title ?? "untitled") + start + end }
            public var title: String?
            public var start: String
            public var end: String
            public var allDay: Bool
        }
        public struct FreeBlock: Codable, Identifiable {
            public var id: String { start + end }
            public var start: String
            public var end: String
        }
        public var conflicts: [Conflict]
        public var freeBlocks: [FreeBlock]

        enum CodingKeys: String, CodingKey {
            case conflicts
            case freeBlocks = "free_blocks"
        }
    }

    public struct Milestone: Codable, Identifiable, Hashable {
        public var id: String { stableKey }
        public var stableKey: String
        public var reminderIdentifier: String?
        public var title: String
        public var notes: String?
        public var due: String?                // ISO
        public var isCompleted: Bool
        public var importancePoints: Int       // 0..1000; all milestones sum to 1000

        enum CodingKeys: String, CodingKey {
            case stableKey, title, notes, due, isCompleted, importancePoints
            case reminderIdentifier = "reminderIdentifier"
        }
    }

    public struct WorkDay: Codable, Identifiable {
        public struct Block: Codable, Identifiable {
            public var id: String { start + (relatedMilestoneKey ?? "") }
            public var start: String
            public var end: String
            public var focus: String
            public var relatedMilestoneKey: String?

            enum CodingKeys: String, CodingKey {
                case start, end, focus
                case relatedMilestoneKey = "relatedMilestoneKey"
            }
        }
        public var id: String { date }
        public var date: String                // YYYY-MM-DD
        public var blocks: [Block]
    }

    public struct InputEcho: Codable {
        public struct TF: Codable { public var start: String; public var end: String }
        public var goal: String
        public var timeframe: TF
    }

    public var status: String
    public var input: InputEcho
    public var smartGoal: SmartGoal
    public var eventsSummary: EventSummary
    public var milestones: [Milestone]
    public var workPlan: [WorkDay]
    public var assumptions: [String]
    public var risks: [String]
    public var notes: [String]

    enum CodingKeys: String, CodingKey {
        case status, input, milestones, assumptions, risks, notes
        case smartGoal = "smart_goal"
        case eventsSummary = "events_summary"
        case workPlan = "work_plan"
    }

    // MARK: - Hashable & Equatable (manual)
    public static func == (lhs: PlanResponse, rhs: PlanResponse) -> Bool {
        lhs.smartGoal.statement == rhs.smartGoal.statement &&
        lhs.input.timeframe.start == rhs.input.timeframe.start &&
        lhs.input.timeframe.end == rhs.input.timeframe.end
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(smartGoal.statement)
        hasher.combine(input.timeframe.start)
        hasher.combine(input.timeframe.end)
    }
}

// MARK: - Date helpers

public enum PlanningDate {
    static let iso8601Z: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    public static func date(fromISO string: String) -> Date? {
        // Try full ISO first (with fractional), then without.
        if let d = iso8601Z.date(from: string) { return d }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        if let d = f.date(from: string) { return d }
        // Finally, accept YYYY-MM-DD (ET)
        if string.count == 10, string.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil {
            let df = DateFormatter()
            df.calendar = Calendar(identifier: .gregorian)
            df.locale = Locale(identifier: "en_US_POSIX")
            df.timeZone = TimeZone(identifier: "America/New_York")
            df.dateFormat = "yyyy-MM-dd"
            return df.date(from: string)
        }
        return nil
    }

    public static func yyyyMMdd(from d: Date) -> String {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(identifier: "America/New_York")
        df.dateFormat = "yyyy-MM-dd"
        return df.string(from: d)
    }
}
