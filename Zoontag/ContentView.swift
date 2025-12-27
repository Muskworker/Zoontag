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
                    List(search.topFacets) { facet in
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
                    .listStyle(.inset)
                }
            }

            Spacer()

            if let err = search.lastError {
                Text(err)
                    .foregroundStyle(.red)
                    .font(.footnote)
            }
        }
        .padding()
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
                Text(item.tags.prefix(3).joined(separator: ", "))
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
                    FlowWrap(tags: item.tags) { tag in
                        Text(tag)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.gray.opacity(0.15)))
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
                FlowWrap(tags: tags) { tag in
                    HStack(spacing: 6) {
                        Text(tag)
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
                    .background(RoundedRectangle(cornerRadius: 12).fill(tint.opacity(0.12)))
                }
            }
        }
    }
}

/// Simple flow layout for chips.
struct FlowWrap<T: Hashable, Content: View>: View {
    let tags: [T]
    let content: (T) -> Content

    @State private var totalHeight: CGFloat = .zero

    var body: some View {
        GeometryReader { geo in
            self.generateContent(in: geo)
        }
        .frame(height: totalHeight)
    }

    private func generateContent(in geo: GeometryProxy) -> some View {
        var x: CGFloat = 0
        var y: CGFloat = 0

        return ZStack(alignment: .topLeading) {
            ForEach(tags, id: \.self) { tag in
                content(tag)
                    .padding(.trailing, 6)
                    .padding(.bottom, 6)
                    .alignmentGuide(.leading) { d in
                        if (x + d.width) > geo.size.width {
                            x = 0
                            y -= d.height
                        }
                        let result = x
                        x += d.width
                        return result
                    }
                    .alignmentGuide(.top) { d in
                        let result = y
                        return result
                    }
            }
        }
        .background(
            GeometryReader { geo2 in
                Color.clear
                    .onAppear { totalHeight = geo2.size.height }
                    .onChange(of: geo2.size.height) { _, h in totalHeight = h }
            }
        )
    }
}
