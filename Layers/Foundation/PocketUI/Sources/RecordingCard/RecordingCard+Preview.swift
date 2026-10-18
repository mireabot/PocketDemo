import SwiftUI

#Preview("Light") {
    RecordingCardPreview()
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    RecordingCardPreview()
        .preferredColorScheme(.dark)
}

#Preview("Large text") {
    RecordingCardPreview()
        .environment(\.dynamicTypeSize, .accessibility3)
}

private struct RecordingCardPreview: View {
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                RecordingCard(
                    title: "Thoughts on a slower morning",
                    summary: "A few ideas for making mornings feel less rushed. Keep the first hour free of notifications, take a short walk, and leave room to think before the day begins. Try preparing breakfast the night before and writing down just one thing to focus on.",
                    updatedAt: Date(),
                    status: .init(title: "Waiting to sync", systemImage: "arrow.triangle.2.circlepath")
                )
                RecordingCard(
                    title: "A little place by the sea",
                    summary: "Find a small place near the water, bring a book, and keep the itinerary open.",
                    updatedAt: Date().addingTimeInterval(-86400)
                )
            }
            .padding(16)
        }
        .background(PocketPalette.screen)
    }
}
