//
//  Palette.swift
//  Scoreline
//
//  Created by Mehul Jasti on 9/28/25.
//


//
//  Palette.swift
//  Scoreline
//
//  Created by Mehul Jasti on 9/29/25.
//

import SwiftUI

/// Central color tokens used throughout the app.
/// Keep these semantic names stable; adjust only the underlying values if you want to retheme.
enum Palette {
    // Ink (text)
    static let ink            = Color(.sRGB, red: 38/255,  green: 38/255,  blue: 43/255,  opacity: 1)
    static let inkSecondary   = Color(.sRGB, red: 74/255,  green: 74/255,  blue: 80/255,  opacity: 0.85)
    static let inkTertiary    = Color(.sRGB, red: 74/255,  green: 74/255,  blue: 80/255,  opacity: 0.65)

    // Accents
    static let amethyst       = Color(.sRGB, red: 167/255, green: 139/255, blue: 250/255, opacity: 1)
    static let goldSoft       = Color(.sRGB, red: 253/255, green: 224/255, blue: 130/255, opacity: 1)
    static let skySoft        = Color(.sRGB, red: 189/255, green: 219/255, blue: 255/255, opacity: 1)
    static let mintSoft       = Color(.sRGB, red: 197/255, green: 243/255, blue: 220/255, opacity: 1)
    static let roseSoft       = Color(.sRGB, red: 255/255, green: 214/255, blue: 222/255, opacity: 1)
    static let lavenderSoft   = Color(.sRGB, red: 237/255, green: 233/255, blue: 254/255, opacity: 1)

    // Backgrounds
    static let bgTop          = Color(.sRGB, red: 250/255, green: 247/255, blue: 255/255, opacity: 1)
    static let bgBottom       = Color(.sRGB, red: 255/255, green: 246/255, blue: 246/255, opacity: 1)

    // Cards / Containers
    static let cardTop        = Color(.sRGB, red: 255/255, green: 252/255, blue: 245/255, opacity: 1)
    static let cardBottom     = Color(.sRGB, red: 246/255, green: 244/255, blue: 255/255, opacity: 1)
    static let dayCard        = Color(.sRGB, red: 255/255, green: 255/255, blue: 255/255, opacity: 0.92)
    static let strip          = Color(.sRGB, red: 246/255, green: 245/255, blue: 255/255, opacity: 1)
    static let sheetBg        = Color(.sRGB, red: 253/255, green: 252/255, blue: 255/255, opacity: 1)

    // Chips / Badges
    static let chipSky        = Color(.sRGB, red: 219/255, green: 234/255, blue: 254/255, opacity: 1)
    static let chipMint       = Color(.sRGB, red: 209/255, green: 250/255, blue: 229/255, opacity: 1)
    static let chipRose       = Color(.sRGB, red: 254/255, green: 226/255, blue: 226/255, opacity: 1)
    static let coinBadge      = Color(.sRGB, red: 254/255, green: 249/255, blue: 195/255, opacity: 1)
    static let badgeLavender  = Color(.sRGB, red: 237/255, green: 233/255, blue: 254/255, opacity: 1)

    // Shadows
    static let shadow         = Color.black.opacity(0.08)
}