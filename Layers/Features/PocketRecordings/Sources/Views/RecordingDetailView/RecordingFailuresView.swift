import Domain
import PocketUI
import SwiftUI

struct RecordingFailuresView: View {
    let failures: [FailedChange]
    let onDiscard: () -> Void

    @ScaledMetric(relativeTo: .headline) private var headingSize = 18

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Changes not synced")
                .font(.system(size: headingSize, weight: .semibold))
            ForEach(failures) { failure in Text(failure.message).foregroundStyle(.red) }
            Button("Discard failed changes", role: .destructive, action: onDiscard)
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle(radius: 8))
                .controlSize(.large)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PocketPalette.surface, in: .rect(cornerRadius: 24))
    }
}
