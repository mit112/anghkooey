import SwiftUI

/// Minimal review sheet for a single captured card draft.
///
/// Presents the resolved text with Accept and Skip actions.
/// The caller (AppState) advances the queue on either action.
/// CardAuthor integration is wired in M3.9.
struct CardReviewSheet: View {
    let draft: AppState.CardDraft
    let onAccept: () -> Void
    let onSkip: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(draft.resolvedText)
                    .font(.body)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("Review Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip", action: onSkip)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Accept", action: onAccept)
                }
            }
        }
    }
}
