//
//  Theme.swift
//  WS1 App Uploader
//
//  Air Force Reserve Mission Mobile design tokens.
//

import SwiftUI

enum Theme {

    // MARK: - Brand Palette

    /// Deep Air Force blue (#003087) — reserved for **backgrounds**:
    /// the hero card, the primary button fill, the insignia gradient.
    /// White text on top of this color is highly legible.  Do not use
    /// it as a foreground/text color on dark surfaces — it disappears.
    static let airForceBlue   = Color(red: 0.0,   green: 48.0 / 255.0, blue: 135.0 / 255.0)

    /// Bright sky-blue (#5DA9FF) — used for **foreground** elements
    /// (text, icons, sidebar tint, secondary-button borders).  Stays
    /// readable on both light and dark backgrounds while still feeling
    /// like an Air Force / aviation accent.
    static let brandAccent    = Color(red: 0.365, green: 0.663,        blue: 1.0)

    /// Mid-range accent used for the brand gradient (between the deep
    /// navy and bright sky).  Brightened so it also reads well as a
    /// foreground color on dark surfaces.
    static let skyAccent      = Color(red: 0.31,  green: 0.66,         blue: 1.0)

    /// Muted silver used for chrome and dividers.
    static let silver         = Color(red: 0.78,  green: 0.80,         blue: 0.83)

    /// Subtle gray surface (cards on dark mode).
    static let surfaceDark  = Color(red: 0.10, green: 0.12,         blue: 0.16)

    /// Surface used in light mode.
    static let surfaceLight = Color(red: 0.96, green: 0.97,         blue: 0.99)

    /// Action red — used sparingly for retirement / destructive accents.
    static let actionRed    = Color(red: 0.78, green: 0.13,         blue: 0.16)

    /// Success green for completed uploads.
    static let success      = Color(red: 0.16, green: 0.62,         blue: 0.36)

    /// Warning amber for in-progress / attention.
    static let warning      = Color(red: 0.95, green: 0.62,         blue: 0.16)

    // MARK: - Layout Tokens

    enum Spacing {
        static let xs: CGFloat  = 4
        static let sm: CGFloat  = 8
        static let md: CGFloat  = 12
        static let lg: CGFloat  = 20
        static let xl: CGFloat  = 32
        static let xxl: CGFloat = 48
    }

    enum Radius {
        static let sm: CGFloat = 6
        static let md: CGFloat = 12
        static let lg: CGFloat = 18
    }
}

// MARK: - Surface Modifier

struct CardSurface: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .padding(Theme.Spacing.lg)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .fill(scheme == .dark ? Theme.surfaceDark : Theme.surfaceLight)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .stroke(Theme.silver.opacity(scheme == .dark ? 0.15 : 0.35), lineWidth: 1)
            )
    }
}

extension View {
    func cardSurface() -> some View { modifier(CardSurface()) }
}
