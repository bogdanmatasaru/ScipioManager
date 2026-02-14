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
                .frame(minWidth: 300)

            if let fw = selectedFramework {
                FrameworkDetailView(framework: fw, dependencies: dependencies)
            } else {
                ContentUnavailableView(
                    "Select a Framework",
                    systemImage: "shippingbox",
                    description: Text("Choose a framework from the list to see details.")
                )
            }
        }
        .navigationTitle("Frameworks (\(frameworks.count))")
        .searchable(text: $searchText, prompt: "Filter frameworks...")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAddSheet = true
                } label: {
                    Label("Add Framework", systemImage: "plus")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await loadFrameworks() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
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

    private var frameworkList: some View {
        List(filteredFrameworks, selection: $selectedFramework) { fw in
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(fw.displayName)
                        .font(.body)
                        .fontWeight(.medium)
                    if let version = fw.version {
                        Text(version)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(fw.sizeFormatted)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 2) {
                        ForEach(fw.slices, id: \.identifier) { slice in
                            Image(systemName: slice.identifier.contains("simulator") ? "desktopcomputer" : "iphone")
                                .font(.caption2)
                                .foregroundStyle(.green)
                        }
                    }
                }
            }
            .padding(.vertical, 2)
            .contextMenu {
                Button("Remove") {
                    frameworkToRemove = fw
                    showRemoveConfirm = true
                }
            }
            .tag(fw)
        }
    }

    private func loadFrameworks() async {
        guard let scipioDir = appState.scipioDir else { return }
        let service = ScipioService(scipioDir: scipioDir)

        if let fws = try? await service.discoverFrameworks() {
            frameworks = fws
        }

        if let buildPkg = appState.buildPackageURL {
            dependencies = (try? PackageParser.parseDependencies(from: buildPkg)) ?? []

            // Enrich frameworks with dependency info
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

        // Find the dependency URL for this framework
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

        // Delete the xcframework from disk
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
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(framework.displayName)
                            .font(.title2)
                            .fontWeight(.bold)
                        if let version = framework.version {
                            Text("Version: \(version)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text(framework.source.rawValue)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(framework.source == .fork ? .orange.opacity(0.2) : .blue.opacity(0.2),
                                    in: Capsule())
                }

                Divider()

                // Slices
                GroupBox("Architecture Slices") {
                    ForEach(framework.slices, id: \.identifier) { slice in
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text(slice.identifier)
                                .font(.system(.body, design: .monospaced))
                            Spacer()
                            Text(slice.platform)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }

                // Info
                GroupBox("Details") {
                    LabeledContent("Size", value: framework.sizeFormatted)
                    if let url = framework.url {
                        LabeledContent("Repository") {
                            Link(url, destination: URL(string: url)!)
                                .font(.caption)
                        }
                    }
                    LabeledContent("XCFramework", value: "\(framework.name).xcframework")
                }

                Spacer()
            }
            .padding()
        }
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
        VStack(spacing: 16) {
            Text("Add Framework")
                .font(.title2)
                .fontWeight(.bold)

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
        }
        .padding()
        .frame(width: 450)
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
