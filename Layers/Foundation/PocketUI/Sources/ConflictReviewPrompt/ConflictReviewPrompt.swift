import SwiftUI

public struct ConflictReviewPrompt: View {
    let fields: [String]
    let onReview: () -> Void

    @ScaledMetric(relativeTo: .title3) private var headingSize = 20
    @ScaledMetric(relativeTo: .footnote) private var fieldSize = 14
    @ScaledMetric(relativeTo: .caption) private var captionSize = 12

    public init(fields: [String], onReview: @escaping () -> Void) {
        self.fields = fields
        self.onReview = onReview
    }

    public var body: some View {
        Button(action: onReview) {
            ConflictReviewCard(surface: PocketPalette.screen) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("NEEDS YOUR REVIEW")
                        .font(.system(size: captionSize))
                        .foregroundStyle(.secondary)
                    Text(heading)
                        .font(.system(size: headingSize, weight: .semibold))
                        .tracking(-0.3)
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(spacing: 0) {
                        ForEach(fields, id: \.self) { field in
                            fieldRow(field)
                        }
                    }
                    HStack(spacing: 8) {
                        Text("Review changes")
                        Image(systemName: "arrow.right")
                            .font(.system(size: fieldSize))
                            .accessibilityHidden(true)
                    }
                    .font(.system(size: fieldSize, weight: .medium))
                    .frame(minHeight: 24)
                }
            }
            .contentShape(.rect(cornerRadius: 24))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Review conflicting edits")
        .accessibilityValue(fields.joined(separator: ", "))
        .accessibilityHint("Opens the conflicting fields so you can choose which edits to keep.")
    }

    private var heading: String {
        switch fields.count {
        case 1: "One field changed in two places"
        case 2: "Two fields changed in two places"
        default: "\(fields.count) fields changed in two places"
        }
    }

    private func fieldRow(_ field: String) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                Text(field)
                    .fixedSize()
                Spacer(minLength: 12)
                conflictStatus
                    .fixedSize()
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(field)
                conflictStatus
            }
        }
        .font(.system(size: fieldSize))
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(PocketPalette.separator)
                .frame(height: 1)
        }
    }

    private var conflictStatus: some View {
        HStack(spacing: 8) {
            Circle()
                .frame(width: 4, height: 4)
                .accessibilityHidden(true)
            Text("Conflicting edits")
                .font(.system(size: captionSize))
        }
        .foregroundStyle(.secondary)
    }
}
