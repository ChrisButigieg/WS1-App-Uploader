//
//  BrandHeader.swift
//  WS1 App Uploader
//
//  Air Force Reserve Mission Mobile Program branding banner.
//

import SwiftUI

/// Reusable branded header — used at the top of the sidebar and the
/// Dashboard.  Falls back to SF Symbol + typography in lieu of a
/// shipped logo asset.
struct BrandHeader: View {
    var compact: Bool = false

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            insignia
            if !compact {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mission Mobile")
                        .font(.system(.title3, design: .serif, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("Air Force Reserve")
                        .font(.caption)
                        .tracking(2)
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Theme.Spacing.sm)
    }

    private var insignia: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Theme.airForceBlue, Theme.skyAccent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: compact ? 28 : 38, height: compact ? 28 : 38)
            Image(systemName: "airplane")
                .font(.system(size: compact ? 14 : 18, weight: .bold))
                .foregroundStyle(.white)
                .rotationEffect(.degrees(-45))
        }
        .accessibilityLabel("Air Force Reserve Mission Mobile")
    }
}

#Preview {
    VStack(alignment: .leading) {
        BrandHeader()
        BrandHeader(compact: true)
    }
    .padding()
}
