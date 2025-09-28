//
//  OnboardingView.swift
//  Scoreline
//
//  Created by Mehul Jasti on 9/27/25.
//

import SwiftUI
import AuthenticationServices
import CryptoKit
import Security

struct OnboardingView: View {
    @Environment(SessionViewModel.self) private var session
    @StateObject private var perms = PermissionsManager()

    @State private var currentNonce: String?
    @State private var stepSignedIn = false

    private var signedIn: Bool { session.user != nil || stepSignedIn }

    private var allDone: Bool {
        signedIn && perms.calendarAuthorized && perms.remindersAuthorized
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text("Welcome to Scoreline")
                        .font(.largeTitle).bold()
                    Text("Let’s get you set up in three quick steps.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 12)

                VStack(spacing: 16) {
                    // Step 1: Sign in
                    StepRow(
                        index: 1,
                        title: "Sign in with Apple",
                        done: signedIn
                    ) {
                        SignInWithAppleButton(.signIn, onRequest: { request in
                            let nonce = randomNonceString()
                            currentNonce = nonce
                            request.requestedScopes = [.fullName, .email]
                            request.nonce = sha256(nonce)
                        }, onCompletion: { result in
                            switch result {
                            case .success(let auth):
                                guard
                                    let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                                    let tokenData = credential.identityToken,
                                    let identityToken = String(data: tokenData, encoding: .utf8),
                                    let rawNonce = currentNonce
                                else { return }

                                let code = credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
                                let comps = credential.fullName
                                let parts = [comps?.givenName, comps?.middleName, comps?.familyName]
                                    .compactMap { $0 }
                                    .filter { !$0.isEmpty }
                                let displayName = parts.isEmpty ? nil : parts.joined(separator: " ")

                                Task {
                                    await session.completeSignIn(
                                        identityToken: identityToken,
                                        nonce: rawNonce,
                                        authorizationCode: code,
                                        appleUser: credential.user,
                                        email: credential.email,
                                        fullName: displayName
                                    )
                                    stepSignedIn = true
                                    session.promoteIfReady(
                                        calendarAuthorized: perms.calendarAuthorized,
                                        remindersAuthorized: perms.remindersAuthorized
                                    )
                                }
                            case .failure(let err):
                                print("Apple sign-in failed: \(err)")
                            }
                        })
                        .signInWithAppleButtonStyle(.black)
                        .frame(height: 48)
                        .disabled(signedIn) // gray out after sign-in
                        .opacity(signedIn ? 0.5 : 1)
                    }

                    // Step 2: Calendar
                    StepRow(
                        index: 2,
                        title: "Allow Calendar access",
                        done: perms.calendarAuthorized
                    ) {
                        Button(perms.calendarAuthorized ? "Calendar Access Granted" : "Grant Calendar Access") {
                            Task {
                                await perms.requestCalendarAccess()
                                session.promoteIfReady(
                                    calendarAuthorized: perms.calendarAuthorized,
                                    remindersAuthorized: perms.remindersAuthorized
                                )
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(perms.calendarAuthorized)   // gray out if already granted
                        .opacity(perms.calendarAuthorized ? 0.5 : 1)
                    }

                    // Step 3: Reminders
                    StepRow(
                        index: 3,
                        title: "Allow Reminders access",
                        done: perms.remindersAuthorized
                    ) {
                        Button(perms.remindersAuthorized ? "Reminders Access Granted" : "Grant Reminders Access") {
                            Task {
                                await perms.requestRemindersAccess()
                                session.promoteIfReady(
                                    calendarAuthorized: perms.calendarAuthorized,
                                    remindersAuthorized: perms.remindersAuthorized
                                )
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(perms.remindersAuthorized)  // gray out if already granted
                        .opacity(perms.remindersAuthorized ? 0.5 : 1)
                    }
                }

                Spacer(minLength: 12)

                Button {
                    session.promoteIfReady(
                        calendarAuthorized: perms.calendarAuthorized,
                        remindersAuthorized: perms.remindersAuthorized
                    )
                } label: {
                    Text(allDone ? "Continue" : "Complete all steps to continue")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!allDone)

                Text("You can change permissions anytime in Settings.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .onAppear {
                perms.refreshStatuses()
                session.promoteIfReady(
                    calendarAuthorized: perms.calendarAuthorized,
                    remindersAuthorized: perms.remindersAuthorized
                )
            }
            .onChange(of: perms.calendarAuthorized) { old, new in
                guard old != new else { return }
                session.promoteIfReady(
                    calendarAuthorized: perms.calendarAuthorized,
                    remindersAuthorized: perms.remindersAuthorized
                )
            }
            .onChange(of: perms.remindersAuthorized) { old, new in
                guard old != new else { return }
                session.promoteIfReady(
                    calendarAuthorized: perms.calendarAuthorized,
                    remindersAuthorized: perms.remindersAuthorized
                )
            }
        }
    }

    private var sessionPromotable: Bool { session.user != nil }
}

// StepRow stays unchanged
private struct StepRow<Controls: View>: View {
    let index: Int
    let title: String
    let done: Bool
    @ViewBuilder var controls: () -> Controls

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Circle()
                    .fill(done ? Color.green.opacity(0.2) : Color.gray.opacity(0.15))
                    .overlay(
                        Group {
                            if done {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.green)
                            } else {
                                Text("\(index)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    )
                    .frame(width: 28, height: 28)

                Text(title)
                    .font(.headline)
                Spacer()
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(done ? .green : .gray)
            }
            .padding(.bottom, 4)

            controls()
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
