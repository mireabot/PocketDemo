import SwiftUI

public struct ConflictReviewAction: View {
    private let title: String
    private let role: ButtonRole?
    private let action: () -> Void

    public init(_ title: String, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.title = title
        self.role = role
        self.action = action
    }

    public var body: some View {
        Button(role: role, action: action) {
            Text(title)
                .foregroundStyle(PocketPalette.label)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .center)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.roundedRectangle(radius: 8))
        .controlSize(.large)
    }
}
