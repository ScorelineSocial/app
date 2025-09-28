//
//  AppleSignIn.swift
//  Scoreline
//
//  Created by Mehul Jasti on 9/27/25.
//

import SwiftUI
import AuthenticationServices
import CryptoKit
import Security

struct LoginView: View {
    @Environment(SessionViewModel.self) private var session
    @State private var currentNonce: String?

    var body: some View {
        VStack(spacing: 24) {
            Text("Grindstone")
                .font(.largeTitle).bold()

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
                        let identityTokenData = credential.identityToken,
                        let identityToken = String(data: identityTokenData, encoding: .utf8),
                        let rawNonce = currentNonce
                    else { return }

                    let authorizationCode = credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
                    let fullName = PersonNameComponentsFormatter().string(from: credential.fullName ?? PersonNameComponents())
                    let email = credential.email

                    Task {
                        await session.completeSignIn(
                            identityToken: identityToken,
                            nonce: rawNonce,
                            authorizationCode: authorizationCode,
                            appleUser: credential.user,
                            email: email,
                            fullName: fullName.isEmpty ? nil : fullName
                        )
                    }

                case .failure(let error):
                    print("Apple sign-in failed: \(error)")
                }
            })
            .signInWithAppleButtonStyle(.black)
            .frame(height: 48)
            .padding(.horizontal, 24)
        }
    }
}

// MARK: - Crypto helpers

func sha256(_ input: String) -> String {
    let data = Data(input.utf8)
    let digest = SHA256.hash(data: data)
    return digest.map { String(format: "%02x", $0) }.joined()
}

func randomNonceString(length: Int = 32) -> String {
    let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
    var result = ""
    var remaining = length

    while remaining > 0 {
        var random: UInt8 = 0
        let status = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
        if status != errSecSuccess { continue }
        if random < charset.count {
            result.append(charset[Int(random) % charset.count])
            remaining -= 1
        }
    }
    return result
}
