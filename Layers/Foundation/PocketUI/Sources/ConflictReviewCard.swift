import SwiftUI

public struct ConflictReviewCard<Content: View>: View {
    private let surface: Color
    private let content: Content

    public init(surface: Color = PocketPalette.surface, @ViewBuilder content: () -> Content) {
        self.surface = surface
        self.content = content()
    }

    public var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(PocketPalette.label)
            .background(surface, in: .rect(cornerRadius: 24))
            .overlay {
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(PocketPalette.border, lineWidth: 1)
            }
    }
}
