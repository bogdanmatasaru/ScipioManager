import SwiftUI

struct FrameworksView: View {
    @Environment(AppState.self) private var appState
    @State private var frameworks: [FrameworkInfo] = []
    @State private var dependencies: [ParsedDependency] = []
    @State private var searchText = ""
    @State private var selectedFramework: FrameworkInfo?
    @State private var showAddSheet = false
    @State private var showRemoveConfirm = false
    @State private var frameworkToRemove: FrameworkInfo?

    var filteredFrameworks: [FrameworkInfo] {
        if searchText.isEmpty { return frameworks }
        return frameworks.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.productName.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        HSplitView {
            frameworkList
                .frame(minWidth: 260, idealWidth: 320, maxWidth: 400)

            if let fw = selectedFramework {
                FrameworkDetailView(framework: fw, dependencies: dependencies)
            } else {
                ContentUnavailableView(
                    "Select a Framework",
                    systemImage: "shippingbox",
                    description: Text("Choose a framework from the list to see details.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Frameworks")
        .navigationSubtitle("\(frameworks.count) total")
        .searchable(text: $searchText, prompt: "Filter...")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 4) {
                    Button {
                        Task { await loadFrameworks() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    Button {
                        showAddSheet = true
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddFrameworkSheet { await loadFrameworks() }
        }
        .alert("Remove Framework?", isPresented: $showRemoveConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                if let fw = frameworkToRemove {
                    Task { await removeFramework(fw) }
                }
            }
        } message: {
            if let fw = frameworkToRemove {
                Text("This will remove \(fw.name) from Build/Package.swift and delete the xcframework from disk.")
            }
        }
        .task { await loadFrameworks() }
    }

    // MARK: - Framework List

    private var frameworkList: some View {
        List(filteredFrameworks, selection: $selectedFramework) { fw in
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(fw.displayName)
                        .fontWeight(.medium)
                    if let version = fw.version {
                        Text(version)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Text(fw.sizeFormatted)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fontDesign(.monospaced)

                // Slice indicator dots
                HStack(spacing: 3) {
                    let hasDevice = fw.slices.contains { !$0.identifier.contains("simulator") }
                    let hasSim = fw.slices.contains { $0.identifier.contains("simulator") }
                    Circle()
                        .fill(hasDevice ? .green : .red.opacity(0.4))
                        .frame(width: 6, height: 6)
                    Circle()
                        .fill(hasSim ? .blue : .red.opacity(0.4))
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.vertical, 2)
            .contextMenu {
                Button("Remove...") {
                    frameworkToRemove = fw
                    showRemoveConfirm = true
                }
            }
            .tag(fw)
        }
    }

    // MARK: - Logic

    private func loadFrameworks() async {
        guard let scipioDir = appState.scipioDir else { return }
        let service = ScipioService(scipioDir: scipioDir)

        if let fws = try? await service.discoverFrameworks() {
            frameworks = fws
        }

        if let buildPkg = appState.buildPackageURL {
            dependencies = (try? PackageParser.parseDependencies(from: buildPkg)) ?? []

            frameworks = frameworks.map { fw in
                var updated = fw
                if let dep = dependencies.first(where: { d in
                    d.products.contains(fw.name) ||
                    d.packageName.caseInsensitiveCompare(fw.name) == .orderedSame
                }) {
                    updated = FrameworkInfo(
                        name: fw.name,
                        productName: fw.productName,
                        version: dep.version,
                        source: dep.isCustomFork ? .fork : .official,
                        url: dep.url,
                        slices: fw.slices,
                        sizeBytes: fw.sizeBytes,
                        cacheStatus: fw.cacheStatus
                    )
                }
                return updated
            }
        }
    }

    private func removeFramework(_ fw: FrameworkInfo) async {
        guard let buildPkg = appState.buildPackageURL,
              let scipioDir = appState.scipioDir else { return }

        if let dep = dependencies.first(where: { d in
            d.products.contains(fw.name) ||
            d.packageName.caseInsensitiveCompare(fw.name) == .orderedSame
        }) {
            try? PackageParser.removeDependency(
                from: buildPkg,
                packageURL: dep.url,
                productNames: dep.products
            )
        }

        let fwPath = scipioDir
            .appendingPathComponent("Frameworks/XCFrameworks")
            .appendingPathComponent("\(fw.name).xcframework")
        try? FileManager.default.removeItem(at: fwPath)

        appState.addActivity("Removed \(fw.name)", type: .info)
        await loadFrameworks()
    }
}

// MARK: - Framework Detail

struct FrameworkDetailView: View {
    let framework: FrameworkInfo
    let dependencies: [ParsedDependency]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(framework.displayName)
                            .font(.title)
                            .fontWeight(.bold)
                        if let version = framework.version {
                            Text("v\(version)")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text(framework.source.rawValue)
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            framework.source == .fork ? .orange.opacity(0.15) : .blue.opacity(0.1),
                            in: Capsule()
                        )
                        .foregroundStyle(framework.source == .fork ? .orange : .blue)
                }

                // Info grid
                Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 10) {
                    GridRow {
                        Text("Size").foregroundStyle(.secondary)
                        Text(framework.sizeFormatted)
                    }
                    if let url = framework.url {
                        GridRow {
                            Text("Repository").foregroundStyle(.secondary)
                            Link(url, destination: URL(string: url)!)
                                .font(.callout)
                                .lineLimit(1)
                        }
                    }
                    GridRow {
                        Text("XCFramework").foregroundStyle(.secondary)
                        Text("\(framework.name).xcframework")
                            .fontDesign(.monospaced)
                            .font(.callout)
                    }
                }
                .font(.body)

                Divider()

                // Architecture slices
                VStack(alignment: .leading, spacing: 10) {
                    Text("Architecture Slices")
                        .font(.headline)

                    ForEach(framework.slices, id: \.identifier) { slice in
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text(slice.identifier)
                                .font(.system(.body, design: .monospaced))
                            Spacer()
                            Text(slice.platform)
                                .foregroundStyle(.secondary)
                                .font(.callout)
                        }
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle(framework.displayName)
    }
}

// MARK: - Add Framework Sheet

struct AddFrameworkSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var url = ""
    @State private var version = ""
    @State private var productName = ""
    @State private var versionType: ParsedDependency.VersionType = .exact
    @State private var error: String?

    var onComplete: () async -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                Text("Add Framework")
                    .font(.headline)
                Text("Add a new SPM dependency to Build/Package.swift")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 20)
            .padding(.bottom, 12)

            Form {
                TextField("Repository URL", text: $url, prompt: Text("https://github.com/..."))
                    .onChange(of: url) {
                        if productName.isEmpty {
                            productName = PackageParser.extractPackageName(from: url)
                        }
                    }

                TextField("Product Name", text: $productName, prompt: Text("LibraryName"))

                Picker("Version Type", selection: $versionType) {
                    Text("Exact").tag(ParsedDependency.VersionType.exact)
                    Text("From").tag(ParsedDependency.VersionType.from)
                    Text("Revision").tag(ParsedDependency.VersionType.revision)
                    Text("Branch").tag(ParsedDependency.VersionType.branch)
                }

                TextField("Version", text: $version, prompt: Text("1.0.0"))

                if let error {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Add") {
                    Task { await addFramework() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(url.isEmpty || version.isEmpty || productName.isEmpty)
            }
            .padding(20)
        }
        .frame(width: 440)
    }

    private func addFramework() async {
        guard let buildPkg = appState.buildPackageURL else {
            error = "Build Package.swift not found"
            return
        }

        do {
            try PackageParser.addDependency(
                to: buildPkg,
                url: url,
                version: version,
                versionType: versionType,
                productName: productName
            )
            appState.addActivity("Added \(productName) to Build/Package.swift", type: .success)
            await onComplete()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
