import SwiftUI
import AppKit

struct ContentView: View {
    @StateObject private var search = MetadataSearchController()
    @State private var state = QueryState()
    @State private var isDetailPaneVisible = true
    @State private var newTagName: String = ""
    @State private var newTagColor: FinderTagColorOption = .none
    @State private var tagEditError: String?
    @State private var userOverrodeTagColor = false
    @State private var suppressTagColorChange = false
    @State private var isEditingTags = false
    @State private var highlightedSuggestionID: String?

    @State private var selection: SearchResultItem? = nil

    var body: some View {
        HSplitView {
            sidebar
                .frame(minWidth: 250, idealWidth: 300, maxWidth: 420)

            mainGrid
                .frame(minWidth: 420, maxWidth: .infinity)

            if isDetailPaneVisible {
                inspector
                    .frame(minWidth: 320, idealWidth: 360, maxWidth: 560)
            }
        }
        .onChange(of: state) { _, newValue in
            search.run(state: newValue)
        }
        .onChange(of: selection) { _, newSelection in
            if newSelection == nil {
                newTagName = ""
                tagEditError = nil
                highlightedSuggestionID = nil
                setTagColor(.none, userInitiated: false)
            }
        }
        .onChange(of: newTagName) { _, newValue in
            handleTagNameChange(newValue)
        }
        .onChange(of: search.results) { _, _ in
            syncHighlightedSuggestion()
        }
        .onChange(of: search.topFacets) { _, _ in
            syncHighlightedSuggestion()
        }
        .onChange(of: newTagColor) { _, _ in
            if suppressTagColorChange {
                suppressTagColorChange = false
            } else {
                userOverrodeTagColor = true
            }
        }
        .onAppear {
            // Start blank; user chooses a folder.
        }
        .frame(minWidth: 1000, minHeight: 650)
        .toolbar {
            ToolbarItemGroup {
                Button("Choose Folder…") { chooseFolder() }
                Divider()

                if search.isSearching {
                    ProgressView()
                        .controlSize(.small)
                }

                Text("Results: \(search.results.count)")
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    toggleDetailPane()
                } label: {
                    Image(systemName: "sidebar.right")
                }
                .help(isDetailPaneVisible ? "Hide Details" : "Show Details")
                .accessibilityLabel(isDetailPaneVisible ? "Hide Details" : "Show Details")

                // Simple “clear all” for fast iteration
                Button("Clear Tags") {
                    state.includeTags.removeAll()
                    state.excludeTags.removeAll()
                }
                .disabled(state.includeTags.isEmpty && state.excludeTags.isEmpty)
            }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                GroupBox("Query") {
                    VStack(alignment: .leading, spacing: 8) {
                        tagChips(title: "Include", tags: Array(state.includeTags).sorted(), tint: .green) { tag in
                            state.includeTags.remove(tag)
                        }

                        tagChips(title: "Exclude", tags: Array(state.excludeTags).sorted(), tint: .red) { tag in
                            state.excludeTags.remove(tag)
                        }
                    }
                    .padding(.top, 4)
                }

                GroupBox("Top tags in results") {
                    if state.scopeURLs.isEmpty {
                        Text("Choose a folder to begin.")
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 4)
                    } else if search.topFacets.isEmpty {
                        Text("No tags found in current results.")
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 4)
                    } else {
                        let groups = facetGroups(from: search.topFacets)
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(groups) { group in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: 8) {
                                        if let color = colorFromHex(group.colorHex) {
                                            Circle()
                                                .fill(color)
                                                .frame(width: 12, height: 12)
                                        } else {
                                            Circle()
                                                .stroke(Color.gray.opacity(0.4), lineWidth: 1)
                                                .frame(width: 12, height: 12)
                                        }
                                        Text(colorLabel(for: group.colorHex))
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                    }

                                    LazyVStack(alignment: .leading, spacing: 6) {
                                        ForEach(group.facets) { facet in
                                            HStack(spacing: 10) {
                                                Button {
                                                    include(tag: facet.tag)
                                                } label: {
                                                    Image(systemName: "plus.circle.fill")
                                                        .foregroundStyle(.green)
                                                }
                                                .buttonStyle(.plain)

                                                Button {
                                                    exclude(tag: facet.tag)
                                                } label: {
                                                    Image(systemName: "minus.circle.fill")
                                                        .foregroundStyle(.red)
                                                }
                                                .buttonStyle(.plain)

                                                if let color = colorFromHex(facet.colorHex) {
                                                    Circle()
                                                        .fill(color)
                                                        .frame(width: 10, height: 10)
                                                }

                                                Text(facet.tag)
                                                    .lineLimit(1)

                                                Spacer()
                                                Text("\(facet.count)")
                                                    .foregroundStyle(.secondary)
                                                    .monospacedDigit()
                                            }
                                            .contentShape(Rectangle())
                                            .contextMenu {
                                                Button("Include") { include(tag: facet.tag) }
                                                Button("Exclude") { exclude(tag: facet.tag) }
                                            }
                                        }
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                }

                if let err = search.lastError {
                    Text(err)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
    }

    // MARK: - Main grid

    private var mainGrid: some View {
        ScrollView {
            if state.scopeURLs.isEmpty {
                VStack(spacing: 10) {
                    Text("Zoontag")
                        .font(.largeTitle)
                    Text("Pick a folder, then refine by tags like a booru.")
                        .foregroundStyle(.secondary)
                    Button("Choose Folder…") { chooseFolder() }
                        .padding(.top, 6)
                }
                .frame(maxWidth: .infinity, minHeight: 400)
            } else {
                let columns = Array(repeating: GridItem(.adaptive(minimum: 140), spacing: 14), count: 1)
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(search.results) { item in
                        resultCard(item)
                            .onTapGesture {
                                selection = item
                            }
                    }
                }
                .padding()
            }
        }
    }

    private func resultCard(_ item: SearchResultItem) -> some View {
        let isSelected = (selection?.id == item.id)

        return VStack(alignment: .leading, spacing: 8) {
            FileThumbnailView(url: item.url, maxDimension: 120)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)

            Text(item.displayName)
                .font(.system(size: 12))
                .lineLimit(2)

            if !item.tags.isEmpty {
                Text(item.tagNames.prefix(3).joined(separator: ", "))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text(" ")
                    .font(.system(size: 11))
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isSelected ? Color.accentColor : Color.gray.opacity(0.25),
                              lineWidth: isSelected ? 2 : 1)
        )
    }

    // MARK: - Inspector

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let item = selection {
                Text(item.displayName)
                    .font(.title3)

                Text(item.url.path)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                Text("Preview")
                    .font(.headline)

                QuickLookPreviewContainer(url: item.url)
                    .frame(maxHeight: dynamicPreviewHeight(for: item))

                Divider()

                Text("Tags")
                    .font(.headline)

                if item.tags.isEmpty {
                    Text("No tags.")
                        .foregroundStyle(.secondary)
                } else {
                    let columns = [GridItem(.adaptive(minimum: 120), spacing: 8, alignment: .leading)]
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                        ForEach(item.tags) { tag in
                            HStack(spacing: 6) {
                                if let color = colorFromHex(tag.colorHex) {
                                    Circle()
                                        .fill(color)
                                        .frame(width: 10, height: 10)
                                }
                                Text(tag.name)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Button {
                                    removeTagFromSelection(tag)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                                .help("Remove tag")
                                .disabled(isEditingTags)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.gray.opacity(0.15)))
                        }
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Add Tag")
                        .font(.headline)
                    HStack(spacing: 8) {
                        AutocompleteTagTextField(placeholder: "Tag name",
                                                 text: $newTagName,
                                                 onMoveUp: {
                            moveSuggestionSelection(delta: -1)
                        }, onMoveDown: {
                            moveSuggestionSelection(delta: 1)
                        }, onTabComplete: {
                            acceptHighlightedSuggestion()
                        }, onSubmit: {
                            addTagToSelection()
                            return true
                        })
                            .frame(minWidth: 160)

                        Picker("Color", selection: $newTagColor) {
                            ForEach(FinderTagColorOption.allCases) { option in
                                HStack {
                                    if let hex = option.hexValue,
                                       let color = colorFromHex(hex) {
                                        Circle()
                                            .fill(color)
                                            .frame(width: 10, height: 10)
                                    }
                                    Text(option.title)
                                }
                                .tag(option)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 130)

                        Button {
                            addTagToSelection()
                        } label: {
                            Label("Add", systemImage: "plus.circle.fill")
                        }
                        .disabled(newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selection == nil || isEditingTags)
                    }

                    if !tagSuggestions.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(tagSuggestions.enumerated()), id: \.element.id) { _, entry in
                                let isHighlighted = highlightedSuggestionID == entry.id
                                Button {
                                    selectSuggestion(entry)
                                } label: {
                                    HStack(spacing: 8) {
                                        if let hex = entry.color.hexValue,
                                           let color = colorFromHex(hex) {
                                            Circle()
                                                .fill(color)
                                                .frame(width: 8, height: 8)
                                        }
                                        Text(entry.displayName)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        Text("Use")
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(isHighlighted ? Color.accentColor.opacity(0.2) : Color.clear)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.15)))
                    }
                }

                if let error = tagEditError {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.footnote)
                } else if isEditingTags {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Updating tags…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                HStack {
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([item.url])
                    }
                    Button("Open") {
                        NSWorkspace.shared.open(item.url)
                    }
                }
            } else {
                Text("Select an item")
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding()
        .frame(minWidth: 320)
    }

    // MARK: - Tag ops

    private func include(tag: String) {
        state.excludeTags.remove(tag)
        state.includeTags.insert(tag)
    }

    private func exclude(tag: String) {
        state.includeTags.remove(tag)
        state.excludeTags.insert(tag)
    }

    private func addTagToSelection() {
        guard let target = selection?.url else { return }
        let trimmed = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let tag = FinderTag(name: trimmed, colorHex: newTagColor.hexValue)
        performTagEdit(target: target, resetInput: true) {
            try FinderTagEditor.addTag(tag, to: target)
        }
    }

    private func removeTagFromSelection(_ tag: FinderTag) {
        guard let target = selection?.url else { return }
        performTagEdit(target: target, resetInput: false) {
            try FinderTagEditor.removeTag(named: tag.name, from: target)
        }
    }

    private func performTagEdit(target: URL, resetInput: Bool, action: @escaping () throws -> [FinderTag]) {
        guard !isEditingTags else { return }
        isEditingTags = true
        tagEditError = nil
        Task {
            do {
                let updated = try action()
                await MainActor.run {
                    applySelectionUpdate(url: target, tags: updated)
                    if resetInput {
                        newTagName = ""
                        setTagColor(.none, userInitiated: false)
                    }
                    search.run(state: state)
                }
            } catch {
                await MainActor.run {
                    tagEditError = error.localizedDescription
                }
            }
            await MainActor.run {
                isEditingTags = false
            }
        }
    }

    private func applySelectionUpdate(url: URL, tags: [FinderTag]) {
        let displayName = selection?.displayName ?? url.lastPathComponent
        selection = SearchResultItem(url: url, displayName: displayName, tags: tags)
    }

    private func handleTagNameChange(_ value: String) {
        syncHighlightedSuggestion()

        if let resolved = TagAutocompleteLogic.resolvedColor(for: value,
                                                             in: tagCatalog,
                                                             userOverrodeColor: userOverrodeTagColor) {
            setTagColor(resolved, userInitiated: false)
        }
    }

    private func setTagColor(_ color: FinderTagColorOption, userInitiated: Bool) {
        if newTagColor == color {
            if !userInitiated {
                userOverrodeTagColor = false
            }
            suppressTagColorChange = false
            return
        }
        suppressTagColorChange = true
        newTagColor = color
        if !userInitiated {
            userOverrodeTagColor = false
        }
    }

    private func applySuggestion(_ entry: TagAutocompleteEntry) {
        newTagName = entry.displayName
        highlightedSuggestionID = entry.id
        setTagColor(entry.color, userInitiated: false)
    }

    private func selectSuggestion(_ entry: TagAutocompleteEntry) {
        applySuggestion(entry)
    }

    private func moveSuggestionSelection(delta: Int) -> Bool {
        guard let id = TagAutocompleteLogic.movedHighlightedSuggestionID(in: tagSuggestions,
                                                                         currentID: highlightedSuggestionID,
                                                                         delta: delta) else {
            return false
        }
        highlightedSuggestionID = id
        return true
    }

    private func acceptHighlightedSuggestion() -> Bool {
        guard let entry = TagAutocompleteLogic.acceptedSuggestion(in: tagSuggestions,
                                                                  highlightedID: highlightedSuggestionID) else {
            return false
        }
        applySuggestion(entry)
        return true
    }

    private func syncHighlightedSuggestion() {
        highlightedSuggestionID = TagAutocompleteLogic.preferredHighlightedSuggestionID(in: tagSuggestions,
                                                                                        previousID: highlightedSuggestionID)
    }

    // MARK: - Folder picker

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Choose"

        if panel.runModal() == .OK, let url = panel.url {
            state.scopeURLs = [url]
            selection = nil
            newTagName = ""
            highlightedSuggestionID = nil
            setTagColor(.none, userInitiated: false)
        }
    }

    private func toggleDetailPane() {
        isDetailPaneVisible.toggle()
    }

    // MARK: - Chip UI

    private func tagChips(title: String, tags: [String], tint: Color, onRemove: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)

            if tags.isEmpty {
                Text("—")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 2)
            } else {
                let columns = [GridItem(.adaptive(minimum: 140), spacing: 8, alignment: .leading)]
                LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                    ForEach(tags, id: \.self) { tag in
                        HStack(spacing: 6) {
                            Text(tag)
                                .lineLimit(1)
                            Button {
                                onRemove(tag)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(tint.opacity(0.8))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 12).fill(tint.opacity(0.12)))
                    }
                }
            }
        }
    }
}

private struct AutocompleteTagTextField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    let onMoveUp: () -> Bool
    let onMoveDown: () -> Bool
    let onTabComplete: () -> Bool
    let onSubmit: () -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: text)
        field.placeholderString = placeholder
        field.delegate = context.coordinator
        field.isBezeled = true
        field.isBordered = true
        field.focusRingType = .default
        field.bezelStyle = .roundedBezel
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        if nsView.placeholderString != placeholder {
            nsView.placeholderString = placeholder
        }
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: AutocompleteTagTextField

        init(_ parent: AutocompleteTagTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl,
                     textView: NSTextView,
                     doCommandBy commandSelector: Selector) -> Bool {
            // Intercept navigation and completion keys so text entry can drive autocomplete.
            switch commandSelector {
            case #selector(NSResponder.moveUp(_:)):
                return parent.onMoveUp()
            case #selector(NSResponder.moveDown(_:)):
                return parent.onMoveDown()
            case #selector(NSResponder.insertTab(_:)):
                return parent.onTabComplete()
            case #selector(NSResponder.insertNewline(_:)):
                return parent.onSubmit()
            default:
                return false
            }
        }
    }
}

extension ContentView {
    private func dynamicPreviewHeight(for item: SearchResultItem) -> CGFloat {
        let base: CGFloat = 320
        let extra: CGFloat = CGFloat(item.tags.count) * 12
        return min(max(base + extra, 320), 560)
    }
}

private struct FacetGroup: Identifiable {
    let key: String
    let colorHex: String?
    let facets: [TagFacet]
    var id: String { key }
}

private extension ContentView {

    var tagCatalog: [String: TagAutocompleteEntry] {
        var catalog: [String: TagAutocompleteEntry] = [:]

        func store(name: String, colorHex: String?) {
            let normalized = normalizedTagName(name)
            guard !normalized.isEmpty else { return }
            let color = FinderTagColorOption.from(hex: colorHex)
            if let existing = catalog[normalized] {
                if existing.color == .none && color != .none {
                    catalog[normalized] = TagAutocompleteEntry(id: normalized, displayName: name, color: color)
                }
            } else {
                catalog[normalized] = TagAutocompleteEntry(id: normalized, displayName: name, color: color)
            }
        }

        for item in search.results {
            for tag in item.tags {
                store(name: tag.name, colorHex: tag.colorHex)
            }
        }

        for facet in search.topFacets {
            store(name: facet.tag, colorHex: facet.colorHex)
        }

        return catalog
    }

    var tagSuggestions: [TagAutocompleteEntry] {
        let query = normalizedTagName(newTagName)
        guard !query.isEmpty else { return [] }

        return tagCatalog.values
            .filter { $0.displayName.lowercased().contains(query) && $0.displayName.caseInsensitiveCompare(newTagName) != .orderedSame }
            .sorted { $0.displayName < $1.displayName }
            .prefix(5)
            .map { $0 }
    }

    func normalizedTagName(_ name: String) -> String {
        TagAutocompleteLogic.normalizedName(name)
    }

    func facetGroups(from facets: [TagFacet]) -> [FacetGroup] {
        let grouped = Dictionary(grouping: facets) { ($0.colorHex?.lowercased()) ?? "none" }
        let sortedKeys = grouped.keys.sorted(by: colorGroupSort)
        return sortedKeys.compactMap { key in
            guard let groupFacets = grouped[key] else { return nil }
            let colorHex = key == "none" ? nil : groupFacets.first(where: { $0.colorHex != nil })?.colorHex
            return FacetGroup(key: key, colorHex: colorHex, facets: groupFacets)
        }
    }

    func colorGroupSort(_ lhs: String, _ rhs: String) -> Bool {
        let lhsNone = lhs == "none"
        let rhsNone = rhs == "none"
        if lhsNone == rhsNone {
            return lhs < rhs
        }
        return lhsNone ? false : true
    }

    func colorLabel(for hex: String?) -> String {
        if let name = FinderTagColorOption.displayName(forHex: hex) {
            return name
        }
        if let normalized = FinderTag.normalizedHex(hex) {
            return "#\(normalized)"
        }
        return "No color"
    }

    func colorFromHex(_ hex: String?) -> Color? {
        guard let normalized = FinderTag.normalizedHex(hex),
              let value = Int(normalized, radix: 16) else { return nil }
        let red = Double((value >> 16) & 0xFF) / 255.0
        let green = Double((value >> 8) & 0xFF) / 255.0
        let blue = Double(value & 0xFF) / 255.0
        return Color(.sRGB, red: red, green: green, blue: blue, opacity: 1)
    }
}
