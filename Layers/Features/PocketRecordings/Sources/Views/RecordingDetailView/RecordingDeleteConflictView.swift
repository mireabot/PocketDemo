import Domain
import PocketUI
import SwiftUI

struct RecordingDeleteConflictView: View {
    let conflict: DeleteConflict
    let onResolve: (DeleteResolution) -> Void

    @ScaledMetric(relativeTo: .headline) private var headingSize = 18

    var body: some View {
        ConflictReviewCard {
            VStack(alignment: .leading, spacing: 16) {
                Text("Recording changed before deletion")
                    .font(.system(size: headingSize, weight: .semibold))
                Text(conflict.theirTitle)
                    .fontWeight(.semibold)
                Text(conflict.theirSummary)
                GlassEffectContainer(spacing: 12) {
                    VStack(alignment: .leading, spacing: 12) {
                        ConflictReviewAction("Delete anyway", role: .destructive) { onResolve(.deleteAnyway) }
                        ConflictReviewAction("Keep recording") { onResolve(.keepRecording) }
                    }
                }
            }
        }
    }
}
