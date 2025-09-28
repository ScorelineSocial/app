//
//  APIClient.swift
//  Scoreline
//
//  Created by Mehul Jasti on 9/28/25.
//

import Foundation

actor APIClient {
    static let shared = APIClient(baseURL: URL(string: "http://10.90.47.2:3000")!)

    private let baseURL: URL
    private var accessToken: String?
    private var refreshToken: String?

    // --- Refresh coalescing + cooldown ---
    private var refreshInFlight: Task<Bool, Never>?
    private var lastRefreshFailureAt: Date?
    private let refreshFailureCooldown: TimeInterval = 30

    init(baseURL: URL) {
        self.baseURL = baseURL
    }

    // Visibility helpers
    func hasAccessToken() async -> Bool { accessToken != nil }
    func hasRefreshToken() async -> Bool { refreshToken != nil }

    // Load tokens early (called from app start)
    func loadTokensFromKeychain() async {
        let (accessData, refreshData): (Data?, Data?) = await MainActor.run {
            (Keychain.get(KCKey.accessToken), Keychain.get(KCKey.refreshToken))
        }
        if let d = accessData { self.accessToken = String(data: d, encoding: .utf8) }
        if let d = refreshData { self.refreshToken = String(data: d, encoding: .utf8) }
        #if DEBUG
        print("🔐 APIClient.loadTokensFromKeychain() access:\(self.accessToken != nil) refresh:\(self.refreshToken != nil)")
        #endif
    }

    func postRefreshIfPossible() async -> Bool { await tryRefresh() }

    func setTokens(access: String, refresh: String) async {
        self.accessToken = access
        self.refreshToken = refresh
        #if DEBUG
        print("✅ APIClient.setTokens() set access+refresh")
        #endif
        await MainActor.run {
            Keychain.set(Data(access.utf8), for: KCKey.accessToken)
            Keychain.set(Data(refresh.utf8), for: KCKey.refreshToken)
        }
    }

    func clearTokens() async {
        self.accessToken = nil
        self.refreshToken = nil
        #if DEBUG
        print("🧹 APIClient.clearTokens() cleared access+refresh")
        #endif
        await MainActor.run {
            Keychain.remove(KCKey.accessToken)
            Keychain.remove(KCKey.refreshToken)
        }
    }

    enum AuthError: LocalizedError {
        case notAuthenticated
        var errorDescription: String? { "Not authenticated" }
    }

    func ensureAuthenticated() async throws {
        if accessToken != nil { return }
        if await tryRefresh(), accessToken != nil { return }
        throw AuthError.notAuthenticated
    }

    // MARK: - Generic helpers (no MainActor needed)

    func get<T: Decodable>(_ path: String) async throws -> T {
        let data: Data = try await requestRaw(method: "GET", path: path, queryItems: nil, body: Optional<Data>.none as Data?, allowAutoRefresh: true)
        return try await MainActor.run { try JSONDecoder().decode(T.self, from: data) }
    }

    func get<T: Decodable>(_ path: String, queryItems: [URLQueryItem]) async throws -> T {
        let data: Data = try await requestRaw(method: "GET", path: path, queryItems: queryItems, body: Optional<Data>.none as Data?, allowAutoRefresh: true)
        return try await MainActor.run { try JSONDecoder().decode(T.self, from: data) }
    }

    func postJSON<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T {
        let encoded: Data = try await MainActor.run { try JSONEncoder().encode(body) }
        let payload: Data = try await requestRaw(method: "POST", path: path, queryItems: nil, body: encoded, allowAutoRefresh: true)
        return try await MainActor.run { try JSONDecoder().decode(T.self, from: payload) }
    }

    func deleteJSON<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T {
        let encoded: Data = try await MainActor.run { try JSONEncoder().encode(body) }
        let payload: Data = try await requestRaw(method: "DELETE", path: path, queryItems: nil, body: encoded, allowAutoRefresh: true)
        return try await MainActor.run { try JSONDecoder().decode(T.self, from: payload) }
    }

    func delete(_ path: String) async throws {
        _ = try await requestRaw(method: "DELETE", path: path, queryItems: nil, body: nil, allowAutoRefresh: true)
    }

    func patchJSON<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T {
        let encoded: Data = try await MainActor.run { try JSONEncoder().encode(body) }
        let payload: Data = try await requestRaw(method: "PATCH", path: path, queryItems: nil, body: encoded, allowAutoRefresh: true)
        return try await MainActor.run { try JSONDecoder().decode(T.self, from: payload) }
    }

    // MARK: - Planning API

    func refine(input: RefineRequest) async throws -> RefineResponse {
        let body: Data = try await MainActor.run { try JSONEncoder().encode(input) }
        let data = try await requestRaw(method: "POST", path: "api/refine", queryItems: nil, body: body, allowAutoRefresh: true)
        return try await decodeRefineResponse(from: data, endpoint: "api/refine")
    }

    func plan(input: PlanRequest) async throws -> PlanResponse {
        let body: Data = try await MainActor.run { try JSONEncoder().encode(input) }
        let data = try await requestRaw(method: "POST", path: "api/plan", queryItems: nil, body: body, allowAutoRefresh: true)
        return try await decodePlanResponse(from: data, endpoint: "api/plan")
    }

    // MARK: - Streaming Plan (SSE)

    struct PlanStreamEvent: Decodable {
        let type: String
        let pct: Double?
        let note: String?
        let plan: PlanResponse?
        let code: String?
        let message: String?
    }

    /// Streams /api/plan with SSE and returns the final PlanResponse.
    /// Calls `onProgress(pct, note)` as progress events arrive.
    func planStream(
        input: PlanRequest,
        onProgress: @escaping (Double, String) -> Void
    ) async throws -> PlanResponse {
        // Ensure we have a token (will coalesce refresh if needed)
        if accessToken == nil, refreshToken != nil {
            _ = await tryRefresh()
        }
        guard let token = accessToken else {
            throw AuthError.notAuthenticated
        }

        // Build request: ?stream=1 + Accept: text/event-stream
        var comps = URLComponents(url: url(for: "api/plan"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "stream", value: "1")]
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.addValue("text/event-stream", forHTTPHeaderField: "Accept")
        req.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let body = try await MainActor.run { try JSONEncoder().encode(input) }
        req.httpBody = body

        let (bytes, resp) = try await URLSession.shared.bytes(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        if http.statusCode == 401 {
            // Try a single refresh/retry cycle before failing
            if await tryRefresh(), let t2 = accessToken {
                var retry = req
                retry.setValue("Bearer \(t2)", forHTTPHeaderField: "Authorization")
                let (bytes2, resp2) = try await URLSession.shared.bytes(for: retry)
                return try await consumePlanStream(bytes2, response: resp2, onProgress: onProgress)
            }
        }
        try Self.throwIfNot2xx(resp, data: Data()) // best-effort for non-2xx
        return try await consumePlanStream(bytes, response: resp, onProgress: onProgress)
    }

    private func consumePlanStream(
        _ bytes: URLSession.AsyncBytes,
        response: URLResponse,
        onProgress: @escaping (Double, String) -> Void
    ) async throws -> PlanResponse {
        var buffer = Data()

        for try await chunk in bytes {
            buffer.append(chunk)

            // SSE frames are separated by \n\n
            while let range = buffer.range(of: Data([0x0A, 0x0A])) { // "\n\n"
                let frame = buffer.subdata(in: 0..<range.lowerBound)
                buffer.removeSubrange(0..<range.upperBound)

                guard let text = String(data: frame, encoding: .utf8) else { continue }

                // Extract last data: line
                let dataLines = text
                    .split(separator: "\n")
                    .filter { $0.hasPrefix("data:") }
                    .map { String($0.dropFirst(5)).trimmingCharacters(in: .whitespaces) }

                guard let jsonLine = dataLines.last,
                      let jsonData = jsonLine.data(using: .utf8) else { continue }

                let evt = try JSONDecoder().decode(PlanStreamEvent.self, from: jsonData)
                switch evt.type {
                case "progress":
                    onProgress(evt.pct ?? 0, evt.note ?? "")
                case "result":
                    if let plan = evt.plan {
                        return plan
                    } else {
                        throw NSError(domain: "PlanStream", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing plan in result event"])
                    }
                case "error":
                    let msg = evt.message ?? evt.note ?? "Unknown error"
                    throw NSError(domain: "PlanStream", code: -2, userInfo: [NSLocalizedDescriptionKey: msg])
                default:
                    // ignore unrecognized types
                    break
                }
            }
        }

        throw NSError(domain: "PlanStream", code: -3, userInfo: [NSLocalizedDescriptionKey: "Stream ended without result"])
    }

    // MARK: - Milestones & Me API

    // /api/me
    @MainActor
    func getMe() async throws -> MeDTO {
        try await get("/api/me")
    }

    enum StatusFilter: String {
        case all, open, completed
    }

    /// GET active plan (optionally with status filter). Returns (plan?, milestones).
    func getActivePlanWithMilestones(status: StatusFilter = .all) async throws -> (PlanDTO?, [MilestoneDTO]) {
        var items: [URLQueryItem] = [
            URLQueryItem(name: "active", value: "1"),
            URLQueryItem(name: "includePlan", value: "1")
        ]
        if status != .all {
            items.append(URLQueryItem(name: "status", value: status.rawValue))
        }

        struct Payload: Decodable {
            let plan: PlanDTO?
            let milestones: [MilestoneDTO]
        }

        let payload: Payload = try await get("/api/milestones", queryItems: items)
        return (payload.plan, payload.milestones)
    }

    /// POST /api/milestones (create plan + milestones, normalize, award points)
    @MainActor
    func postMilestones(body: PostMilestonesBody) async throws -> PostMilestonesResponse {
        try await postJSON("/api/milestones", body: body)
    }

    /// PATCH /api/milestones/[id]
    func patchMilestone(id: Int, body: PatchMilestoneBody) async throws -> MilestonePatchResult {
        let encoded: Data = try encodePatchBodyDisambiguated(body)
        let payload: Data = try await requestRaw(method: "PATCH", path: "/api/milestones/\(id)", queryItems: nil, body: encoded, allowAutoRefresh: true)
        return try await MainActor.run { try JSONDecoder().decode(MilestonePatchResult.self, from: payload) }
    }

    /// POST /api/milestones/sync
    @MainActor
    func syncMilestones(_ deltas: [SyncDelta]) async throws -> SyncResponse {
        try await postJSON("/api/milestones/sync", body: deltas)
    }

    private func encodePatchBodyDisambiguated(_ body: PatchMilestoneBody) throws -> Data {
        struct CodingKeys: CodingKey {
            var stringValue: String
            init?(stringValue: String) { self.stringValue = stringValue }
            var intValue: Int? { nil }
            init?(intValue: Int) { return nil }

            static let title = CodingKeys(stringValue: "title")!
            static let notes = CodingKeys(stringValue: "notes")!
            static let due = CodingKeys(stringValue: "due")!
            static let importancePoints = CodingKeys(stringValue: "importancePoints")!
            static let isCompleted = CodingKeys(stringValue: "isCompleted")!
            static let completedAt = CodingKeys(stringValue: "completedAt")!
            static let reminderIdentifier = CodingKeys(stringValue: "reminderIdentifier")!
            static let reminderExternalIdentifier = CodingKeys(stringValue: "reminderExternalIdentifier")!
        }

        struct Box: Encodable {
            let title: String?
            let notes: String??
            let due: String??
            let importancePoints: Int?
            let isCompleted: Bool?
            let completedAt: String??
            let reminderIdentifier: String??
            let reminderExternalIdentifier: String??

            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)

                if let title { try c.encode(title, forKey: .title) }
                if let importancePoints { try c.encode(importancePoints, forKey: .importancePoints) }
                if let isCompleted { try c.encode(isCompleted, forKey: .isCompleted) }

                // Double optionals: omit / null / value
                if let notesOuter = notes {
                    if let v = notesOuter { try c.encode(v, forKey: .notes) } else { try c.encodeNil(forKey: .notes) }
                }
                if let dueOuter = due {
                    if let v = dueOuter { try c.encode(v, forKey: .due) } else { try c.encodeNil(forKey: .due) }
                }
                if let completedAtOuter = completedAt {
                    if let v = completedAtOuter { try c.encode(v, forKey: .completedAt) } else { try c.encodeNil(forKey: .completedAt) }
                }
                if let remIdOuter = reminderIdentifier {
                    if let v = remIdOuter { try c.encode(v, forKey: .reminderIdentifier) } else { try c.encodeNil(forKey: .reminderIdentifier) }
                }
                if let remExtOuter = reminderExternalIdentifier {
                    if let v = remExtOuter { try c.encode(v, forKey: .reminderExternalIdentifier) } else { try c.encodeNil(forKey: .reminderExternalIdentifier) }
                }
            }
        }

        let box = Box(
            title: body.title,
            notes: body.notes,
            due: body.due,
            importancePoints: body.importancePoints,
            isCompleted: body.isCompleted,
            completedAt: body.completedAt,
            reminderIdentifier: body.reminderIdentifier,
            reminderExternalIdentifier: body.reminderExternalIdentifier
        )

        // No MainActor needed here.
        return try JSONEncoder().encode(box)
    }

    // MARK: - Focus (Pomodoro) API

    struct FocusAwardRequest: Encodable {
        let seconds: Int
    }

    struct FocusAwardResponse: Decodable {
        let awardedPoints: Int
        let totalPoints: Int
    }

    /// POST /api/focus/award  — awards stones for focus seconds (server: 1 per 5 minutes)
    @MainActor
    func awardFocus(seconds: Int) async throws -> FocusAwardResponse {
        try await postJSON("/api/focus/award", body: FocusAwardRequest(seconds: seconds))
    }

    // MARK: - Avatars API

    struct OwnedAvatarsDTO: Decodable {
        /// e.g. ["CatHat","BaldHat","CatBow"]
        let avatars: [String]
    }

    // OPTION #1: client sends cost
    private struct PurchaseAvatarRequest: Encodable {
        let avatarKey: String   // e.g. "CatLeaf", "BaldMason"
        let cost: Int           // client-provided price (server validates)
    }

    /// Matches server union:
    /// { ok: true, avatarKey, spent, remainingStones } | { ok: false, error }
    struct PurchaseAvatarResponse: Decodable {
        let ok: Bool
        let avatarKey: String?
        let spent: Int?
        let remainingStones: Int?
        let error: String?
    }

    /// GET /api/avatars/owned
    @MainActor
    func getOwnedAvatars() async throws -> OwnedAvatarsDTO {
        try await get("/api/avatars/owned")
    }

    /// POST /api/avatars/purchase  (client sends cost)
    @MainActor
    func purchaseAvatar(avatarKey: String, cost: Int) async throws -> PurchaseAvatarResponse {
        try await postJSON("/api/avatars/purchase", body: PurchaseAvatarRequest(avatarKey: avatarKey, cost: cost))
    }

    // MARK: - Core request

    private func requestRaw(
        method: String,
        path: String,
        queryItems: [URLQueryItem]?,
        body: Data?,
        allowAutoRefresh: Bool
    ) async throws -> Data {
        // Build URL with optional query items
        var comps = URLComponents(url: url(for: path), resolvingAgainstBaseURL: false)!
        if let queryItems, !queryItems.isEmpty {
            comps.queryItems = queryItems
        }
        let url = comps.url!

        let isProtectedSync = url.path.hasPrefix("/api/sync/")
        let isAuthRoute = url.path.hasPrefix("/api/auth/")

        if allowAutoRefresh, accessToken == nil, refreshToken != nil {
            _ = await tryRefresh()
        }

        if isProtectedSync, accessToken == nil {
            #if DEBUG
            print("⛔️ APIClient: Blocking request to \(url.absoluteString) because access token is nil")
            #endif
            throw AuthError.notAuthenticated
        }

        var req = URLRequest(url: url)
        req.httpMethod = method
        if let body {
            req.httpBody = body
            req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let token = accessToken {
            req.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else if !isAuthRoute {
            #if DEBUG
            print("⚠️ APIClient: Building request to \(url.absoluteString) without access token")
            #endif
        }

        let (data, resp) = try await URLSession.shared.data(for: req)

        if let http = resp as? HTTPURLResponse, http.statusCode == 401, allowAutoRefresh {
            if await tryRefresh() {
                var retry = req
                if let token = accessToken {
                    retry.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                }
                let (d2, r2) = try await URLSession.shared.data(for: retry)
                try Self.throwIfNot2xx(r2, data: d2)
                return d2
            }
        }

        try Self.throwIfNot2xx(resp, data: data)
        return data
    }

    // MARK: - Tolerant decoders using JSONSerialization

    struct JSONDecodeDebugError: LocalizedError {
        let endpoint: String
        let reason: String
        var errorDescription: String? { "Failed to decode JSON from \(endpoint): \(reason)" }
    }

    @MainActor
    private func decodeRefineResponse(from data: Data, endpoint: String) throws -> RefineResponse {
        let dec = JSONDecoder()

        // 1) Direct decode
        if let direct = try? dec.decode(RefineResponse.self, from: data) { return direct }

        // 2) Attempt tolerant unwrap of `result` or `steps.*.output`
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw JSONDecodeDebugError(endpoint: endpoint, reason: "Non-JSON body") }

        // a) Prefer `result`
        if let result = root["result"] {
            if let subData = try? JSONSerialization.data(withJSONObject: result),
               let decoded = try? dec.decode(RefineResponse.self, from: subData) {
                return decoded
            }
        }

        // b) Fallback to first `steps.*.output` that matches
        if let steps = root["steps"] as? [String: Any] {
            for (_, val) in steps {
                if let dict = val as? [String: Any],
                   let output = dict["output"] {
                    if let subData = try? JSONSerialization.data(withJSONObject: output),
                       let decoded = try? dec.decode(RefineResponse.self, from: subData) {
                        return decoded
                    }
                }
            }
        }

        #if DEBUG
        if let raw = String(data: data, encoding: .utf8) {
            print("❌ Refine decode failed. RAW:\n\(raw)")
        }
        #endif
        throw JSONDecodeDebugError(endpoint: endpoint, reason: "Unexpected response shape")
    }

    @MainActor
    private func decodePlanResponse(from data: Data, endpoint: String) throws -> PlanResponse {
        let dec = JSONDecoder()

        // 1) Direct decode
        if let direct = try? dec.decode(PlanResponse.self, from: data) { return direct }

        // 2) Tolerant unwrap
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw JSONDecodeDebugError(endpoint: endpoint, reason: "Non-JSON body") }

        if let result = root["result"] {
            if let subData = try? JSONSerialization.data(withJSONObject: result),
               let decoded = try? dec.decode(PlanResponse.self, from: subData) {
                return decoded
            }
        }

        if let steps = root["steps"] as? [String: Any] {
            for (_, val) in steps {
                if let dict = val as? [String: Any],
                   let output = dict["output"] {
                    if let subData = try? JSONSerialization.data(withJSONObject: output),
                       let decoded = try? dec.decode(PlanResponse.self, from: subData) {
                        return decoded
                    }
                }
            }
        }

        #if DEBUG
        if let raw = String(data: data, encoding: .utf8) {
            print("❌ Plan decode failed. RAW:\n\(raw)")
        }
        #endif
        throw JSONDecodeDebugError(endpoint: endpoint, reason: "Unexpected response shape")
    }

    private static func throwIfNot2xx(_ resp: URLResponse, data: Data) throws {
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let msg = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw NSError(domain: "API", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])
        }
    }

    // MARK: - Refresh

    private func tryRefresh() async -> Bool {
        if let lastFail = lastRefreshFailureAt, Date().timeIntervalSince(lastFail) < refreshFailureCooldown {
            #if DEBUG
            print("🧯 APIClient.tryRefresh() cooldown active")
            #endif
            return false
        }
        guard let rt = refreshToken else {
            #if DEBUG
            print("🧯 APIClient.tryRefresh() no refresh token")
            #endif
            return false
        }

        if let inflight = refreshInFlight { return await inflight.value }

        struct RefreshPayload: Decodable {
            let ok: Bool
            let appleSub: String?
            let accessToken: String
            let refreshToken: String
            let accessTokenExpiresIn: Int?
            let refreshTokenExpiresIn: Int?
            let name: String?
            let email: String?
        }
        struct Body: Encodable { let refreshToken: String }

        let task = Task { () async -> Bool in
            var succeeded = false
            defer { self.refreshInFlight = nil }

            do {
                var req = URLRequest(url: self.url(for: "api/auth/refresh"))
                req.httpMethod = "POST"
                req.addValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = try JSONEncoder().encode(Body(refreshToken: rt))

                let (data, resp) = try await URLSession.shared.data(for: req)
                try Self.throwIfNot2xx(resp, data: data)

                let payload: RefreshPayload = try JSONDecoder().decode(RefreshPayload.self, from: data)

                await self.setTokens(access: payload.accessToken, refresh: payload.refreshToken)
                self.lastRefreshFailureAt = nil
                succeeded = true
            } catch {
                self.lastRefreshFailureAt = Date()
                #if DEBUG
                print("❌ APIClient.tryRefresh() failed, keeping existing tokens")
                #endif
                succeeded = false
            }

            return succeeded
        }

        refreshInFlight = task
        return await task.value
    }

    private func url(for path: String) -> URL {
        let clean = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return baseURL.appendingPathComponent(clean)
    }
}
