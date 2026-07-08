import SwiftUI
import AnghkooeyCore

/// Flat browse of all cards with tag-filter chips.
///
/// Loads all cards from the store on appear and after each edit-sheet dismiss.
/// Tapping a row opens `LibraryCardEditView`. Tag chips filter the list;
/// tapping a selected chip deselects it (show all).
public struct LibraryView: View {

    let store: any CardStoreProtocol
    private let loadSampleCards: (() async -> Void)?

    @State private var cards: [Card.Snapshot] = []
    @State private var selectedTag: String? = nil
    @State private var editingCard: Card.Snapshot? = nil
    @State private var isLoading = false
    @State private var loadFailed = false
    @State private var showingImport = false
    @State private var showingCreate = false
    @State private var searchText = ""
    @State private var cardPendingDelete: Card.Snapshot? = nil
    @State private var deleteErrorMessage: String? = nil

    public init(store: any CardStoreProtocol, loadSampleCards: (() async -> Void)? = nil) {
        self.store = store
        self.loadSampleCards = loadSampleCards
    }

    private var allTags: [String] {
        Array(Set(cards.flatMap(\.tags))).sorted()
    }

    private var filteredCards: [Card.Snapshot] {
        Self.filter(cards, searchText: searchText, selectedTag: selectedTag)
    }

    /// Pure filter combining the tag-chip selection and the search query with AND semantics.
    ///
    /// - `selectedTag`, when non-nil, keeps only cards whose `tags` contains it.
    /// - `searchText`, when non-empty (after trimming), keeps only cards where the
    ///   question, answer, or any tag contains the query (case-insensitive).
    ///
    /// Static and side-effect-free so it can be unit-tested without a view or store.
    ///
    /// Explicitly `nonisolated`: `LibraryView` conforms to `View`, whose `body`
    /// requirement is `@MainActor`, and Swift infers main-actor isolation onto
    /// the whole conforming type by default — including static members. Without
    /// this annotation, calling `filter` from a non-main-actor context (e.g. a
    /// Swift Testing test function, which runs off the main actor) trips a
    /// runtime actor-isolation assertion. `filter` touches no view/actor state,
    /// so it can safely opt out.
    nonisolated static func filter(
        _ cards: [Card.Snapshot],
        searchText: String,
        selectedTag: String?
    ) -> [Card.Snapshot] {
        var result = cards
        if let tag = selectedTag {
            result = result.filter { $0.tags.contains(tag) }
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            result = result.filter { card in
                card.question.localizedCaseInsensitiveContains(query)
                    || card.answer.localizedCaseInsensitiveContains(query)
                    || card.tags.contains { $0.localizedCaseInsensitiveContains(query) }
            }
        }
        return result
    }

    public var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if loadFailed {
                ContentUnavailableView {
                    Label("Couldn't load your cards", systemImage: "exclamationmark.triangle")
                } description: {
                    Text("Something went wrong. Check your connection and try again.")
                } actions: {
                    Button("Retry") { Task { await load() } }
                        .buttonStyle(.borderedProminent)
                }
            } else if cards.isEmpty {
                ContentUnavailableView {
                    Label("No cards yet", systemImage: "rectangle.stack")
                } description: {
                    Text("Add a card, import your Anki deck, or try a sample.")
                } actions: {
                    Button("Add a card") { showingCreate = true }
                        .buttonStyle(.borderedProminent)
                        .accessibilityLabel("Add a new card")
                    Button("Import from Anki") { showingImport = true }
                    if let loader = loadSampleCards {
                        Button("Load sample deck") {
                            Task { await loader(); await load() }
                        }
                    }
                }
            } else {
                cardList
            }
        }
        .navigationTitle("Library")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingCreate = true
                } label: {
                    Label("Add Card", systemImage: "plus")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingImport = true
                } label: {
                    Label("Import", systemImage: "tray.and.arrow.down")
                }
            }
        }
        .task { await load() }
        .sheet(item: $editingCard) { card in
            LibraryCardEditView(mode: .edit(card), store: store) {
                Task { await load() }
            }
        }
        .sheet(isPresented: $showingCreate) {
            LibraryCardEditView(mode: .create, store: store) {
                Task { await load() }
            }
        }
        .sheet(isPresented: $showingImport) {
            AnkiImportView(
                importer: LiveAnkiImporter(store: store),
                isPresented: $showingImport
            )
            .onDisappear { Task { await load() } }
        }
    }

    // MARK: - Card list

    private var cardList: some View {
        let filtered = filteredCards
        let trimmedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filterIsActive = !trimmedQuery.isEmpty || selectedTag != nil

        return List {
            if !allTags.isEmpty {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            filterChip(label: "All", isSelected: selectedTag == nil) {
                                selectedTag = nil
                            }
                            ForEach(allTags, id: \.self) { tag in
                                filterChip(label: tag, isSelected: selectedTag == tag) {
                                    selectedTag = selectedTag == tag ? nil : tag
                                }
                            }
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 4)
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            Section {
                ForEach(filtered) { card in
                    Button {
                        editingCard = card
                    } label: {
                        cardRow(card)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            cardPendingDelete = card
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            } header: {
                Text("\(filtered.count) card\(filtered.count == 1 ? "" : "s")")
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $searchText)
        .overlay {
            if filtered.isEmpty && filterIsActive {
                if !trimmedQuery.isEmpty {
                    ContentUnavailableView.search(text: trimmedQuery)
                } else {
                    ContentUnavailableView.search
                }
            }
        }
        .confirmationDialog(
            "Delete this card?",
            isPresented: Binding(
                get: { cardPendingDelete != nil },
                set: { if !$0 { cardPendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let card = cardPendingDelete {
                    Task { await deleteCard(card) }
                }
            }
            Button("Cancel", role: .cancel) { cardPendingDelete = nil }
        } message: {
            Text("This can't be undone.")
        }
        .alert(
            "Couldn't delete the card",
            isPresented: Binding(
                get: { deleteErrorMessage != nil },
                set: { if !$0 { deleteErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteErrorMessage ?? "")
        }
    }

    private func cardRow(_ card: Card.Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(card.question)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(2)
            if !card.tags.isEmpty {
                Text(card.tags.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func filterChip(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    isSelected ? Color.accentColor : Color(.secondarySystemFill),
                    in: Capsule()
                )
                .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
        // The visual capsule stays compact; the frame below only expands the
        // tappable region to meet the 44pt minimum hit-target guideline.
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityHint("Filters the card list")
    }

    // MARK: - Data

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            cards = try await store.allCards()
            loadFailed = false
            // A stale chip selection (tag deleted/removed elsewhere) would
            // otherwise show an empty list with no visibly-selected chip.
            if let tag = selectedTag, !cards.contains(where: { $0.tags.contains(tag) }) {
                selectedTag = nil
            }
        } catch {
            loadFailed = true
            UILog.library.error("Library load failed: \(error)")
        }
    }

    /// Deletes `card` and reloads. Only posts `.anghkooeyDeckDidChange` and
    /// reloads AFTER a successful delete — a failed delete leaves the list
    /// untouched and surfaces `deleteErrorMessage` instead (#38).
    private func deleteCard(_ card: Card.Snapshot) async {
        defer { cardPendingDelete = nil }
        do {
            try await store.delete(id: card.id)
            NotificationCenter.default.post(name: .anghkooeyDeckDidChange, object: card.id)
            await load()
        } catch {
            UILog.library.error("Card delete failed: \(error)")
            deleteErrorMessage = "Couldn't delete the card — try again."
        }
    }
}
