//
//  ScorelineApp.swift
//  Scoreline
//
//  Created by Mehul Jasti on 9/27/25.
//

import SwiftUI
import EventKit

@main
struct ScorelineApp: App {
    @State private var session = SessionViewModel()
    @Environment(\.scenePhase) private var scenePhase

    private var permissionsOK: Bool {
        PermissionsManager.isAuthorized(for: .event) && PermissionsManager.isAuthorized(for: .reminder)
    }

    private var rootKey: String {
        let userKey = session.user?.id ?? "anon"
        let permsKey = permissionsOK ? "permsOK" : "permsNO"
        let restoringKey = session.isRestoring ? "restoring" : "ready"
        return "\(userKey)-\(permsKey)-\(restoringKey)"
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if session.isRestoring {
                    ZStack {
                        Color(.systemBackground).ignoresSafeArea()
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("Restoring your session…")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else if let user = session.user, permissionsOK {
                    MainTabView(user: user)
                } else {
                    OnboardingView()
                }
            }
            .id(rootKey)
            .environment(session)
            // Load tokens immediately, then refresh ONLY if we don't have an access token
            .task {
                await APIClient.shared.loadTokensFromKeychain()
                if await APIClient.shared.hasAccessToken() == false,
                   await APIClient.shared.hasRefreshToken() == true {
                    _ = await APIClient.shared.postRefreshIfPossible()
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    Task {
                        if await APIClient.shared.hasAccessToken() == false,
                           await APIClient.shared.hasRefreshToken() == true {
                            _ = await APIClient.shared.postRefreshIfPossible()
                        }
                        // 🔽 Kick off reminders → backend milestone completion sync
                        await MilestonesSyncManager.shared.syncOnForeground()
                    }
                }
            }
        }
    }
}
