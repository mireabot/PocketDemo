import SwiftUI

struct RecordingOverviewView: View {
    let title: String
    let summary: String
    let isPending: Bool

    @ScaledMetric(relativeTo: .title) private var titleSize = 28
    @ScaledMetric(relativeTo: .headline) private var headingSize = 18
    @ScaledMetric(relativeTo: .footnote) private var footnoteSize = 14

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.system(size: titleSize, weight: .semibold))
                if isPending {
                    Text("Waiting to sync")
                        .font(.system(size: footnoteSize))
                        .foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                Text("Summary")
                    .font(.system(size: headingSize, weight: .semibold))
                Text(summary)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
