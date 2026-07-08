import SwiftUI
import AnghkooeyCore

/// Horizontal tag-chip row with an add-tag text field.
///
/// Renders existing tags as removable capsule chips. The user types a new tag
/// and presses Return (or taps Add) to append it. Duplicate names
/// (case-insensitive via `Tag.normalize`) are silently ignored.
struct TagEditorView: View {
    @Binding var tags: [String]
    @State private var newTagText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(tags, id: \.self) { tag in
                            HStack(spacing: 4) {
                                Text(tag)
                                    .font(.caption)
                                    .foregroundStyle(.primary)
                                Button {
                                    tags.removeAll { $0 == tag }
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(Rectangle())
                                .accessibilityLabel("Remove tag \(tag)")
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.12), in: Capsule())
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
            HStack {
                TextField("Add tag…", text: $newTagText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit { commitNewTag() }
                if !newTagText.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button("Add") { commitNewTag() }
                        .buttonStyle(.borderless)
                        .font(.subheadline)
                }
            }
        }
    }

    private func commitNewTag() {
        // Preserve the user's display casing — Tag stores mixed-case `name`;
        // uniqueness is enforced on the normalized form (matches CardStore.findOrCreateTags).
        let trimmed = newTagText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { newTagText = ""; return }
        let normalized = Tag.normalize(trimmed)
        guard !tags.contains(where: { Tag.normalize($0) == normalized }) else { newTagText = ""; return }
        tags.append(trimmed)
        newTagText = ""
    }
}
