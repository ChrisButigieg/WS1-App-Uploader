//
//  Components.swift
//  WS1 App Uploader
//
//  Reusable UI components used throughout the app.
//

import SwiftUI

// MARK: - Status Badge

enum StatusKind {
    case success, warning, failure, info, neutral

    var color: Color {
        switch self {
        case .success: return Theme.success
        case .warning: return Theme.warning
        case .failure: return Theme.actionRed
        case .info:    return Theme.skyAccent
        case .neutral: return Theme.silver
        }
    }

    var symbol: String {
        switch self {
        case .success: return "checkmark.seal.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .failure: return "xmark.octagon.fill"
        case .info:    return "info.circle.fill"
        case .neutral: return "circle.fill"
        }
    }
}

struct StatusBadge: View {
    let text: String
    let kind: StatusKind

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: kind.symbol)
                .font(.caption2)
            Text(text)
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .tracking(0.5)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundStyle(kind.color)
        .background(
            Capsule().fill(kind.color.opacity(0.15))
        )
    }
}

// MARK: - Primary Button Style

struct PrimaryButtonStyle: ButtonStyle {
    var fullWidth: Bool = false
    var destructive: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.md)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                    .fill(destructive ? Theme.actionRed : Theme.airForceBlue)
                    .brightness(configuration.isPressed ? -0.08 : 0)
            )
            .opacity(configuration.isPressed ? 0.92 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .foregroundStyle(Theme.brandAccent)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                    .stroke(Theme.brandAccent, lineWidth: 1.2)
            )
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}

// MARK: - Section Header

struct SectionTitle: View {
    let text: String
    var subtitle: String? = nil
    var icon: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: Theme.Spacing.sm) {
                if let icon {
                    Image(systemName: icon)
                        .foregroundStyle(Theme.brandAccent)
                }
                Text(text)
                    .font(.title3.weight(.semibold))
            }
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Labelled Field

struct LabelledField<Content: View>: View {
    let title: String
    var hint: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .tracking(1)
                .foregroundStyle(.secondary)
            content()
            if let hint {
                Text(hint)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
