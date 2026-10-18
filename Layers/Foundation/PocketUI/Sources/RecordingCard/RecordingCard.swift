import SwiftUI

public struct RecordingCard: View {
    let title: String
    let summary: String
    let updatedAt: Date
    let status: Tag?

    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Environment(\.timeZone) private var timeZone
    @ScaledMetric(relativeTo: .title2) private var titleSize = 24
    @ScaledMetric(relativeTo: .subheadline) private var headingSize = 14
    @ScaledMetric(relativeTo: .body) private var summarySize = 16
    @ScaledMetric(relativeTo: .caption) private var tagSize = 12

    public init(title: String, summary: String, updatedAt: Date, status: Tag? = nil) {
        self.title = title
        self.summary = summary
        self.updatedAt = updatedAt
        self.status = status
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.system(size: titleSize, weight: .semibold))
                .tracking(-0.6)
                .fixedSize(horizontal: false, vertical: true)
            summaryPanel
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { footerTags }
                    .fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: 8) { footerTags }
            }
        }
        .foregroundStyle(PocketPalette.onCard)
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PocketPalette.card, in: .rect(cornerRadius: 24))
        .contentShape(.rect(cornerRadius: 24))
    }

    private var summaryPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Summary")
                .font(.system(size: headingSize, weight: .semibold))
            Text(summary)
                .font(.system(size: summarySize))
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .background(PocketPalette.cardInset)
        .overlay {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.42),
                    .init(color: PocketPalette.cardInset.opacity(0.3), location: 0.68),
                    .init(color: PocketPalette.cardInset, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)
        }
        .clipShape(.rect(cornerRadius: 12))
    }

    @ViewBuilder private var footerTags: some View {
        tag(Tag(title: timestamp))
        if let status { tag(status) }
    }

    private func tag(_ tag: Tag) -> some View {
        HStack(spacing: 4) {
            if let systemImage = tag.systemImage { Image(systemName: systemImage) }
            Text(tag.title)
        }
        .font(.system(size: tagSize))
        .foregroundStyle(PocketPalette.onCardSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(PocketPalette.cardInset, in: .rect(cornerRadius: 4))
    }

    private var timestamp: String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter.string(from: updatedAt)
    }
}
