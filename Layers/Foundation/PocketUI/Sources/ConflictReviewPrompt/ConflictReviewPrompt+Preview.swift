import SwiftUI

#Preview("Title conflict") {
    ConflictReviewPrompt(fields: ["Title"], onReview: {})
        .padding(24)
}

#Preview("Summary conflict") {
    ConflictReviewPrompt(fields: ["Summary"], onReview: {})
        .padding(24)
}

#Preview("Two conflicting fields") {
    ConflictReviewPrompt(fields: ["Title", "Summary"], onReview: {})
        .padding(24)
}

#Preview("Dark") {
    ConflictReviewPrompt(fields: ["Title", "Summary"], onReview: {})
        .padding(24)
        .preferredColorScheme(.dark)
}

#Preview("Large text") {
    ConflictReviewPrompt(fields: ["Title", "Summary"], onReview: {})
        .padding(24)
        .dynamicTypeSize(.accessibility3)
}
