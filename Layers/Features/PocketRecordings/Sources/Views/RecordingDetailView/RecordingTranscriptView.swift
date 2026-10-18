import Domain
import SwiftUI

struct RecordingTranscriptView: View {
    let state: TranscriptState
    let onRetry: () -> Void

    @ScaledMetric(relativeTo: .headline) private var headingSize = 18
    @ScaledMetric(relativeTo: .caption) private var timestampSize = 12

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 16) {
            Text("Transcript")
                .font(.system(size: headingSize, weight: .semibold))
            switch state {
            case let .loaded(transcript):
                ForEach(transcript.segments) { segment in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Duration.milliseconds(segment.startMs).formatted(.time(pattern: .minuteSecond)))
                            .font(.system(size: timestampSize))
                            .foregroundStyle(.secondary)
                        Text(segment.text)
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            case .loading: ProgressView()
            case .waitingForNetwork:
                Text("Available when you're back online.").foregroundStyle(.secondary)
            case .failed:
                Text("Couldn't load the transcript.")
                Button("Retry", action: onRetry)
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.roundedRectangle(radius: 8))
                    .controlSize(.large)
            }
        }
    }
}
