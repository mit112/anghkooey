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
    @State private var showingImport = false
    @State private var showingCreate = false

    public init(store: any CardStoreProtocol, loadSampleCards: (() async -> Void)? = nil) {
        self.store = store
        self.loadSampleCards = loadSampleCards
    }

    private var allTags: [String] {
        Array(Set(cards.flatMap(\.tags))).sorted()
    }

    private var filteredCards: [Card.Snapshot] {
        guard let tag = selectedTag else { return cards }
        return cards.filter { $0.tags.contains(tag) }
    }

    public var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        List {
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
                ForEach(filteredCards) { card in
                    Button {
                        editingCard = card
                    } label: {
                        cardRow(card)
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("\(filteredCards.count) card\(filteredCards.count == 1 ? "" : "s")")
            }
        }
        .listStyle(.insetGrouped)
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
    }

    // MARK: - Data

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            cards = try await store.allCards()
        } catch {
            cards = []
        }
    }
}
