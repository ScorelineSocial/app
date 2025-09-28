//
//  Models.swift
//  Scoreline
//
//  Created by Mehul Jasti on 9/27/25.
//

import Foundation

struct User: Codable, Identifiable {
    var id: String { appleSub }
    let appleSub: String
    let name: String?
    let email: String?
}

struct AuthResponse: Codable {
    let ok: Bool
    let appleSub: String
    let name: String?
    let email: String?
    let accessToken: String
    let refreshToken: String
    let accessTokenExpiresIn: Int?
    let refreshTokenExpiresIn: Int?
}
