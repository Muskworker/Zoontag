import SwiftUI
import AppKit

struct ContentView: View {
    @StateObject private var search = MetadataSearchController()
    @State private var state = QueryState()

    @State private var selection: SearchResultItem? = nil

    var body: some View {
        NavigationSplitView {
            sidebar
        } content: {
            mainGrid
        } detail: {
            inspector
        }
        .onChange(of: state) { _, newValue in
            search.run(state: newValue)
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
            Image(nsImage: item.iconImage(size: 96))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 96)
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
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.gray.opacity(0.15)))
                        }
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

    // MARK: - Folder picker

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Choose"

        if panel.runModal() == .OK, let url = panel.url {
            state.scopeURLs = [url]
        }
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

private struct FacetGroup: Identifiable {
    let key: String
    let colorHex: String?
    let facets: [TagFacet]
    var id: String { key }
}

private extension ContentView {
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
        guard let normalized = normalizedHex(hex) else { return "No color" }
        return "#\(normalized)"
    }

    func colorFromHex(_ hex: String?) -> Color? {
        guard let normalized = normalizedHex(hex),
              let value = Int(normalized, radix: 16) else { return nil }
        let red = Double((value >> 16) & 0xFF) / 255.0
        let green = Double((value >> 8) & 0xFF) / 255.0
        let blue = Double(value & 0xFF) / 255.0
        return Color(.sRGB, red: red, green: green, blue: blue, opacity: 1)
    }

    func normalizedHex(_ hex: String?) -> String? {
        guard var hex = hex?.trimmingCharacters(in: .whitespacesAndNewlines), !hex.isEmpty else { return nil }
        if hex.hasPrefix("#") {
            hex.removeFirst()
        }
        guard hex.count == 6 else { return nil }
        return hex.uppercased()
    }
}
