import Domain
import PocketUI
import SwiftUI

struct RecordingFieldConflictView: View {
    let conflict: FieldConflict
    let onResolve: (FieldResolution) -> Void

    @State private var merged = ""
    @State private var merging = false
    @ScaledMetric(relativeTo: .headline) private var headingSize = 18
    @ScaledMetric(relativeTo: .footnote) private var labelSize = 14
    @ScaledMetric(relativeTo: .caption) private var captionSize = 12

    var body: some View {
        ConflictReviewCard {
            VStack(alignment: .leading, spacing: 16) {
                Text("\(conflict.field.rawValue.capitalized) changed on another device")
                    .font(.system(size: headingSize, weight: .semibold))
                value("Before", text: conflict.base)
                value("Yours", text: conflict.mine)
                value("Theirs", text: conflict.theirs)
                if let device = conflict.changedBy {
                    Text(device)
                        .font(.system(size: captionSize))
                        .foregroundStyle(.secondary)
                }
                resolutionControls
            }
        }
    }

    private var resolutionControls: some View {
        GlassEffectContainer(spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                ConflictReviewAction("Keep mine") { onResolve(.keepMine) }
                ConflictReviewAction("Keep theirs") { onResolve(.keepTheirs) }
                if merging {
                    TextField("Merged \(conflict.field.rawValue)", text: $merged, axis: .vertical)
                        .padding(16)
                        .background(PocketPalette.screen, in: .rect(cornerRadius: 24))
                    ConflictReviewAction("Save merged value") { onResolve(.use(merged)) }
                } else {
                    ConflictReviewAction("Merge manually") { merged = conflict.mine; merging = true }
                }
            }
        }
    }

    private func value(_ label: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: labelSize))
                .foregroundStyle(.secondary)
            Text(text)
                .textSelection(.enabled)
        }
    }
}
