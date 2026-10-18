import Domain
import PocketUI
import SwiftUI

struct RecordingConflictReviewView: View {
    let conflicts: [FieldConflict]
    let onResolve: (FieldConflict, FieldResolution) -> Void

    @State private var reviewing = false

    private var orderedConflicts: [FieldConflict] {
        EditableField.allCases.compactMap { field in
            conflicts.first { $0.field == field }
        }
    }

    var body: some View {
        ConflictReviewPrompt(fields: orderedConflicts.map(\.field.rawValue.capitalized)) {
            reviewing = true
        }
        .sheet(isPresented: $reviewing) {
            NavigationStack {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 28) {
                        Text("Choose which version to keep for each field.")
                            .foregroundStyle(.secondary)
                        ForEach(orderedConflicts, id: \.field) { conflict in
                            RecordingFieldConflictView(conflict: conflict) {
                                onResolve(conflict, $0)
                            }
                        }
                    }
                    .padding(24)
                    .font(.body)
                }
                .background(PocketPalette.screen)
                .navigationTitle("Review conflicting edits")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done", systemImage: "xmark") { reviewing = false }
                    }
                }
            }
            .tint(PocketPalette.label)
            .presentationDragIndicator(.visible)
        }
        .onChange(of: conflicts.isEmpty) { _, isEmpty in
            if isEmpty { reviewing = false }
        }
    }
}
