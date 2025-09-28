//
//  SessionViewModel.swift
//  Scoreline
//
//  Created by Mehul Jasti on 9/27/25.
//

import Foundation
import AuthenticationServices
import Observation

@MainActor
@Observable
final class SessionViewModel {
    var user: User?
    var isRestoring: Bool = true

    // Guard against concurrent restore/sign-in races
    private var restoreEpoch = UUID()

    private var appleUserID: String? {
        didSet {
            if let id = appleUserID {
                Keychain.set(Data(id.utf8), for: KCKey.appleUserID)
            } else {
                Keychain.remove(KCKey.appleUserID)
            }
        }
    }

    init() {
        // Optimistically render from cached user to avoid flashing onboarding
        self.user = loadCachedUser()
        // Load cached Apple user ID so we can check credential state later if needed
        if let data = Keychain.get(KCKey.appleUserID),
           let id = String(data: data, encoding: .utf8) {
            self.appleUserID = id
        }

        let epoch = UUID()
        self.restoreEpoch = epoch
        Task { await restoreSessionOnLaunch(epoch: epoch) }

        NotificationCenter.default.addObserver(
            forName: ASAuthorizationAppleIDProvider.credentialRevokedNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { await self?.signOut() }
        }
    }

    // Race-safe restore that will NOT clear tokens if sign-in happens mid-flight
    private func restoreSessionOnLaunch(epoch: UUID) async {
        if self.restoreEpoch == epoch { self.isRestoring = true }
        defer {
            if self.restoreEpoch == epoch { self.isRestoring = false }
        }

        // 1) Load any saved tokens first
        await APIClient.shared.loadTokensFromKeychain()

        // 2) Try silent refresh (no recursion)
        if await APIClient.shared.postRefreshIfPossible() {
            if let cached = loadCachedUser() { self.user = cached }
            return
        }

        // 3) If sign-in occurred while we were restoring, bail out WITHOUT clearing tokens
        let hasAT = await APIClient.shared.hasAccessToken()
        if hasAT { return }
        let hasRT = await APIClient.shared.hasRefreshToken()
        if hasRT { return }
        if self.user != nil { return }

        // 4) No tokens present; remain unauthenticated (do NOT call signOut which could wipe
        //    anything set by a concurrent sign-in). Let Onboarding show naturally.
        self.user = nil
    }

    func completeSignIn(
        identityToken: String,
        nonce: String,
        authorizationCode: String?,
        appleUser: String,
        email: String?,
        fullName: String?
    ) async {
        struct Body: Encodable {
            let identityToken: String
            let nonce: String
            let authorizationCode: String?
            let email: String?
            let fullName: String?
        }

        do {
            let auth: AuthResponse = try await APIClient.shared.postJSON(
                "/api/auth/apple",
                body: Body(identityToken: identityToken,
                           nonce: nonce,
                           authorizationCode: authorizationCode,
                           email: email,
                           fullName: fullName)
            )

            // Persist tokens immediately (memory + Keychain)
            await APIClient.shared.setTokens(access: auth.accessToken, refresh: auth.refreshToken)

            // Persist Apple ID for silent restore
            self.appleUserID = appleUser

            // Cache minimal profile and set user
            let u = User(appleSub: auth.appleSub, name: auth.name, email: auth.email)
            saveCachedUser(u)
            self.user = u

            // Cancel any in-flight restore epoch by advancing it
            self.restoreEpoch = UUID()
            self.isRestoring = false
        } catch {
            print("Sign-in error: \(error)")
        }
    }

    func signOut() async {
        self.user = nil
        await APIClient.shared.clearTokens()
        // Keep or remove Apple user id depending on your strategy
        // self.appleUserID = nil
        Keychain.remove(KCKey.cachedUser)
    }

    // Called by OnboardingView; implement any gating logic you want here.
    func promoteIfReady(calendarAuthorized: Bool, remindersAuthorized: Bool) {
        // Optional: gate entry on permissions
    }

    private func credentialState(for userID: String) async -> ASAuthorizationAppleIDProvider.CredentialState {
        await withCheckedContinuation { cont in
            ASAuthorizationAppleIDProvider().getCredentialState(forUserID: userID) { state, _ in
                cont.resume(returning: state)
            }
        }
    }

    private func saveCachedUser(_ user: User) {
        if let data = try? JSONEncoder().encode(user) {
            Keychain.set(data, for: KCKey.cachedUser)
        }
    }
    private func loadCachedUser() -> User? {
        if let data = Keychain.get(KCKey.cachedUser) {
            return try? JSONDecoder().decode(User.self, from: data)
        }
        return nil
    }
}
