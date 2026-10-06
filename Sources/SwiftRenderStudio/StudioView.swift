import AppKit
import AVKit
import SwiftUI
import StudioCore

/// Native editing shell. StudioStore owns file panels, project preparation and
/// render jobs; the view only presents their actual state.
struct StudioView: View {
    @Bindable var store: StudioStore
    @State private var section: StudioSection? = .project
    @State private var sourceQuery = ""
    @State private var player: AVPlayer?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        GeometryReader { geometry in
            NavigationSplitView(columnVisibility: $columnVisibility) {
                sidebar
                    .frame(height: geometry.size.height, alignment: .top)
                    .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 230)
            } detail: {
                VStack(spacing: 0) {
                    if let error = store.errorMessage, !error.isEmpty {
                        errorBanner(error)
                        Divider()
                    }
                    HStack(spacing: 0) {
                        Group {
                            switch section ?? .project {
                            case .project: projectView
                            case .sources: sourcesView
                            case .activity: activityView
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        Divider()
                        inspector
                            .frame(width: 280)
                            .frame(maxHeight: .infinity, alignment: .top)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Divider()
                    statusBar
                }
                .frame(maxWidth: .infinity)
                .frame(height: geometry.size.height, alignment: .top)
                .navigationTitle(store.workspaceURL?.lastPathComponent ?? "SwiftRender Studio")
                .toolbar { studioToolbar }
            }
            // Native List/Form containers need the window's finite proposal;
            // their content must not expand the split view beyond the viewport.
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .frame(minWidth: 1000, minHeight: 680)
        .onChange(of: store.movieURL, initial: true) { _, url in
            player?.pause()
            player = url.map(AVPlayer.init(url:))
        }
        .onDisappear { player?.pause() }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $section) {
                Section("Workspace") {
                    ForEach(StudioSection.allCases) { item in
                        Label(item.title, systemImage: item.symbol).tag(item)
                    }
                }
                if let source = store.sourceURL {
                    Section("App source") {
                        VStack(alignment: .leading, spacing: 6) {
                            Label(source.lastPathComponent, systemImage: "folder")
                                .font(.subheadline.weight(.medium))
                                .lineLimit(2)
                            Text(source.deletingLastPathComponent().path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .truncationMode(.middle)
                        }
                        .padding(.vertical, 4)
                        if let inventory = store.inventory {
                            ForEach(inventory.counts.keys.sorted(), id: \.self) { kind in
                                if let count = inventory.counts[kind], count > 0 {
                                    HStack {
                                        Text(kind).lineLimit(1)
                                        Spacer(minLength: 8)
                                        Text(count, format: .number)
                                            .monospacedDigit()
                                            .foregroundStyle(.secondary)
                                            .frame(minWidth: 30, alignment: .trailing)
                                    }
                                    .font(.caption)
                                    .accessibilityElement(children: .combine)
                                }
                            }
                        }
                    }
                }
                if store.workspaceURL != nil {
                    Section {
                        Label(store.isSample ? "Sample project" : "App film project", systemImage: store.isSample ? "sparkles" : "film.stack")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .listStyle(.sidebar)
            Divider()
            VStack(spacing: 8) {
                Button(action: store.chooseSource) {
                    Label(store.sourceURL == nil ? "Choose App…" : "Change App…", systemImage: "folder.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .disabled(store.isBusy)
                if store.workspaceURL != nil {
                    Button(action: store.showProject) {
                        Label("Show Project in Finder", systemImage: "folder")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(store.isBusy)
                }
            }
            .controlSize(.regular)
            .padding(12)
        }
    }

    @ToolbarContentBuilder
    private var studioToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button(action: store.openProject) {
                Label("Open Film Project…", systemImage: "folder")
            }
            .help("Open an existing SwiftRender film project")
            .disabled(store.isBusy)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            if store.workspaceURL != nil {
                Button(action: store.copyCodexBrief) {
                    Label("Copy Brief", systemImage: "doc.on.doc")
                }
                .help("Copy the film brief to continue with Codex")
                .disabled(store.isBusy)
            }
            Button(action: store.renderPreview) {
                Label("Preview", systemImage: "play.rectangle")
            }
            .help("Render a smaller movie to review motion and sound")
            .disabled(!store.canRender || store.isBusy)
            Button(action: store.renderFinal) {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .help("Render the final movie at the selected output size")
            .disabled(!store.canRender || store.isBusy)
        }
    }

    private var projectView: some View {
        VStack(spacing: 0) {
            if store.workspaceURL != nil || store.movieURL != nil {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.settings.title.isEmpty ? "Your film" : store.settings.title)
                            .font(.system(.title2, design: .rounded, weight: .semibold))
                            .lineLimit(1)
                        Text(store.isSample ? "Sample · original demo components" : "App film workspace")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 16)
                    Text(store.settings.aspect.label)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    if store.movieURL != nil {
                        Button(action: store.revealMovie) {
                            Image(systemName: "folder")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Show movie in Finder")
                        .help("Show movie in Finder")
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
                Divider()
            }

            if let player {
                GeometryReader { geometry in
                    StudioMoviePlayer(player: player)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .background(.black)
                        .accessibilityLabel("Rendered film preview")
                }
                .padding(24)
                .background(Color(nsColor: .underPageBackgroundColor))
            } else if let url = store.posterURL, let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .underPageBackgroundColor))
                    .accessibilityLabel("Film preview image")
            } else {
                projectEmptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .underPageBackgroundColor))
            }

            if store.movieURL != nil {
                HStack(spacing: 8) {
                    Image(systemName: "headphones")
                        .accessibilityHidden(true)
                    Text("Review motion and sound together before exporting.")
                    Spacer(minLength: 0)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
            }
        }
    }

    @ViewBuilder
    private var projectEmptyState: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: store.workspaceURL != nil ? "play.rectangle.on.rectangle" : "film.stack")
                .font(.system(.largeTitle, design: .rounded, weight: .light))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 10) {
                Text(emptyTitle)
                    .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(emptyDescription)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(3)
            }
            if store.workspaceURL == nil && store.sourceURL == nil {
                HStack(spacing: 10) {
                    Button("Choose App…", action: store.chooseSource)
                        .buttonStyle(.borderedProminent)
                    Button("Try a Sample", action: store.createSample)
                }
                .disabled(store.isBusy)
                Text("Swift, iOS, and macOS app repositories")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if store.workspaceURL == nil {
                Button("Prepare Film Project…", action: store.prepareProject)
                    .buttonStyle(.borderedProminent)
                    .disabled(!store.canPrepare || store.isBusy)
            } else {
                HStack(spacing: 10) {
                    if store.isSample {
                        Button("Render Preview", action: store.renderPreview)
                            .buttonStyle(.borderedProminent)
                            .disabled(!store.canRender || store.isBusy)
                    } else {
                        Button("Copy Brief for Codex", action: store.copyCodexBrief)
                            .buttonStyle(.borderedProminent)
                            .disabled(store.isBusy)
                    }
                    Button("Show Project", action: store.showProject)
                        .disabled(store.isBusy)
                }
            }
        }
        .frame(maxWidth: 420, alignment: .leading)
        .padding(32)
    }

    private var emptyTitle: String {
        if store.workspaceURL != nil { return store.isSample ? "See the pipeline in motion." : "Your film starts with the app." }
        return store.sourceURL == nil ? "Make your app\nthe story." : "Give your app\na film workspace."
    }

    private var emptyDescription: String {
        if store.workspaceURL != nil {
            return store.isSample
                ? "Render this small demo to explore the workflow. It uses original sample components and can be replaced with your app’s own design."
                : "The source inventory and film brief are ready. Continue in Codex to adapt the app’s actual views, assets, and motion, then return here to preview and export."
        }
        return store.sourceURL == nil
            ? "Choose a repository to build a launch film from its real interface, artwork, and motion."
            : "Set the story and format on the right. Preparing creates a separate project, source inventory, and brief for Codex to turn into your film."
    }

    private var sourcesView: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("App sources")
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                Spacer()
                if let inventory = store.inventory {
                    Text("\(inventory.files.count) files")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .padding(24)
            if let inventory = store.inventory {
                TextField("Filter by file name or type", text: $sourceQuery)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Filter app sources")
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
                Divider()
                let files = inventory.files.filter {
                    sourceQuery.isEmpty || $0.path.localizedCaseInsensitiveContains(sourceQuery) || $0.kind.localizedCaseInsensitiveContains(sourceQuery)
                }
                if files.isEmpty {
                    ContentUnavailableView.search(text: sourceQuery)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(files, id: \.path) { file in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: sourceSymbol(file.kind))
                                .foregroundStyle(.secondary)
                                .frame(width: 20)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 4) {
                                Text((file.path as NSString).lastPathComponent)
                                    .font(.body.weight(.medium))
                                    .lineLimit(1)
                                Text(file.path)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer(minLength: 8)
                            Text(file.kind)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 5)
                        .accessibilityElement(children: .combine)
                        .help(file.path)
                    }
                    .listStyle(.inset)
                }
            } else {
                ContentUnavailableView {
                    Label("No Source Inventory", systemImage: "doc.text.magnifyingglass")
                } description: {
                    Text("Choose an app repository and prepare a film project to see its source files and assets.")
                } actions: {
                    Button("Choose App…", action: store.chooseSource)
                        .disabled(store.isBusy)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var activityView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Activity")
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                Spacer()
                if store.isBusy { ProgressView().controlSize(.small).accessibilityLabel("Task in progress") }
            }
            .padding(24)
            Divider()
            if store.logText.isEmpty {
                ContentUnavailableView {
                    Label("Ready When You Are", systemImage: "terminal")
                } description: {
                    Text("Project preparation and render output appear here.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView([.horizontal, .vertical]) {
                    Text(store.logText)
                        .font(.system(.caption, design: .monospaced))
                        .monospacedDigit()
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(20)
                }
                .background(Color(nsColor: .textBackgroundColor))
            }
        }
    }

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Film brief")
                .font(.system(.headline, design: .rounded))
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
            Divider()
            Form {
                Section("Story") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Title").font(.caption).foregroundStyle(.secondary)
                        TextField("", text: $store.settings.title, prompt: Text("Your app"))
                            .labelsHidden()
                            .accessibilityLabel("Film title")
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("The promise").font(.caption).foregroundStyle(.secondary)
                        TextField("", text: $store.settings.promise, prompt: Text("What should someone remember?"), axis: .vertical)
                            .labelsHidden()
                            .lineLimit(3...5)
                            .accessibilityLabel("Film promise")
                    }
                }
                Section("Output") {
                    Picker("Format", selection: $store.settings.aspect) {
                        ForEach(FilmAspect.allCases) { aspect in
                            Text(aspect.label).monospacedDigit().tag(aspect)
                        }
                    }
                    .pickerStyle(.menu)
                    LabeledContent("Canvas") {
                        Text("\(store.settings.aspect.width) × \(store.settings.aspect.height)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    Picker("Duration", selection: $store.settings.duration) {
                        ForEach(5...60, id: \.self) { seconds in
                            Text("\(seconds) s").monospacedDigit().tag(seconds)
                        }
                    }
                    .pickerStyle(.menu)
                    Picker("Frame rate", selection: $store.settings.fps) {
                        ForEach([24, 30, 60], id: \.self) { fps in
                            Text("\(fps) fps").monospacedDigit().tag(fps)
                        }
                    }
                    .pickerStyle(.menu)
                }
                Section("Soundtrack") {
                    if let path = store.settings.audioPath, !path.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Label((path as NSString).lastPathComponent, systemImage: "waveform")
                                .font(.caption)
                                .lineLimit(2)
                                .help(path)
                            HStack {
                                Button("Replace…", action: store.chooseAudio)
                                Spacer()
                                Button("Remove", action: store.removeAudio)
                            }
                        }
                    } else {
                        Button(action: store.chooseAudio) {
                            Label("Choose Audio…", systemImage: "waveform")
                        }
                        Text("Add a full-length music track, or compose the soundtrack with Codex.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .controlSize(.small)
            .disabled(store.isBusy)

            if store.sourceURL != nil && store.workspaceURL == nil {
                Divider()
                Button("Prepare Film Project…", action: store.prepareProject)
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    .padding(16)
                    .disabled(!store.canPrepare || store.isBusy)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            if store.isBusy {
                ProgressView().controlSize(.small).accessibilityLabel("Task in progress")
            } else {
                Image(systemName: store.errorMessage == nil ? "circle" : "exclamationmark.circle")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            Text(store.statusText)
                .lineLimit(1)
                .truncationMode(.middle)
                .monospacedDigit()
            Spacer(minLength: 16)
            if store.isBusy {
                Button("Cancel", action: store.cancel).controlSize(.small)
            } else if store.workspaceURL != nil {
                Text(store.isSample ? "Sample" : "App project")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(.bar)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(message).textSelection(.enabled).lineLimit(4)
            Spacer(minLength: 8)
            Button("View Activity") { section = .activity }
                .controlSize(.small)
        }
        .font(.callout)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor))
        .accessibilityElement(children: .contain)
    }

    private func sourceSymbol(_ kind: String) -> String {
        let kind = kind.lowercased()
        if kind.contains("metal") || kind.contains("shader") { return "sparkles" }
        if kind.contains("swift") { return "swift" }
        if kind.contains("asset") || kind.contains("image") { return "photo" }
        if kind.contains("font") { return "textformat" }
        if kind.contains("audio") { return "waveform" }
        return "doc.text"
    }
}

private enum StudioSection: String, CaseIterable, Identifiable {
    case project, sources, activity
    var id: Self { self }
    var title: String {
        switch self {
        case .project: "Project"
        case .sources: "Sources"
        case .activity: "Activity"
        }
    }
    var symbol: String {
        switch self {
        case .project: "play.rectangle"
        case .sources: "square.stack.3d.up"
        case .activity: "terminal"
        }
    }
}

/// Use AVKit's AppKit player directly; it also supplies native playback controls.
private struct StudioMoviePlayer: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        view.videoGravity = .resizeAspect
        view.player = player
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player { view.player = player }
    }

    static func dismantleNSView(_ view: AVPlayerView, coordinator: ()) {
        view.player?.pause()
        view.player = nil
    }
}
