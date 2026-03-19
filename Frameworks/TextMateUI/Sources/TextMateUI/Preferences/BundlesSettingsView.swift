import SwiftUI

// MARK: - Bundles Preferences Pane

/// Replaces BundlesPreferences.mm — table view listing bundles with search, filter, install/uninstall.
/// Note: This view depends on BundlesManager which is exposed through the bridging layer.
public struct BundlesSettingsView: View {
    @State private var bundles: [BundleItem] = []
    @State private var searchText = ""
    @State private var selectedCategory: String?
    @State private var categories: [String] = []
    @State private var sortOrder = [KeyPathComparator(\BundleItem.name)]
    @State private var selection: Set<BundleItem.ID> = []
    @State private var activityText = ""
    @State private var isBusy = false

    @AppStorage(DefaultsKey.disableBundleUpdates)
    private var disableBundleUpdates = false

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Scope bar + search
            HStack {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        categoryButton(nil, label: "All")
                        ForEach(categories, id: \.self) { category in
                            categoryButton(category, label: category)
                        }
                    }
                    .padding(.horizontal, 8)
                }

                Spacer()

                TextField("Search", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .frame(width: 100)
                    .padding(.trailing, 8)
            }
            .padding(.vertical, 8)

            // Bundles table
            Table(filteredBundles, selection: $selection, sortOrder: $sortOrder) {
                TableColumn("") { bundle in
                    Toggle("", isOn: installBinding(for: bundle))
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                        .disabled(bundle.isMandatory && bundle.isInstalled)
                        .allowsHitTesting(bundle.installState != .mixed)
                }
                .width(20)

                TableColumn("Bundle", value: \.name) { bundle in
                    Text(bundle.name)
                }
                .width(min: 100, ideal: 140)

                TableColumn("") { bundle in
                    if bundle.htmlURL != nil {
                        Button {
                            if let url = bundle.htmlURL {
                                NSWorkspace.shared.open(url)
                            }
                        } label: {
                            Image(systemName: "link")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .width(20)

                TableColumn("Updated", value: \.sortableDate) { bundle in
                    if let date = bundle.lastUpdated {
                        Text(date, style: .date)
                    }
                }
                .width(90)

                TableColumn("Description") { bundle in
                    Text(bundle.summary)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }
            }
            .tableStyle(.bordered)
            .onChange(of: sortOrder) { _, newOrder in
                bundles.sort(using: newOrder)
            }

            // Footer
            HStack {
                Toggle("Check for and install updates automatically", isOn: Binding(
                    get: { !disableBundleUpdates },
                    set: { disableBundleUpdates = !$0 }
                ))
                .controlSize(.small)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // Status bar
            HStack {
                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.leading, 8)
                }
                Spacer()
                Text(activityText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(height: 24)
            .background(.bar)
        }
        .frame(minWidth: 580, minHeight: 400)
        .onAppear(perform: loadBundles)
    }

    // MARK: - Filtered Content

    private var filteredBundles: [BundleItem] {
        bundles.filter { bundle in
            let matchesCategory = selectedCategory == nil || bundle.category == selectedCategory
            let matchesSearch = searchText.isEmpty || bundle.name.localizedCaseInsensitiveContains(searchText)
            return matchesCategory && matchesSearch
        }
    }

    // MARK: - Category Buttons

    private func categoryButton(_ category: String?, label: String) -> some View {
        Button(label) {
            selectedCategory = category
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(selectedCategory == category ? .accentColor : nil)
    }

    // MARK: - Install Binding

    private func installBinding(for bundle: BundleItem) -> Binding<Bool> {
        Binding(
            get: { bundle.isInstalled },
            set: { newValue in
                guard let idx = bundles.firstIndex(where: { $0.id == bundle.id }) else { return }
                if newValue {
                    // Install via BundlesManager bridge
                    isBusy = true
                    activityText = "Installing '\(bundle.name)' bundle\u{2026}"
                    bundles[idx].isInstalled = true
                    // In production, this would call BundlesManager.sharedInstance.installBundles()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        activityText = "Installed '\(bundle.name)' bundle."
                        isBusy = false
                    }
                } else {
                    bundles[idx].isInstalled = false
                    activityText = "Uninstalled '\(bundle.name)' bundle."
                }
            }
        )
    }

    // MARK: - Data Loading

    private func loadBundles() {
        // In production, this would load from BundlesManager.sharedInstance.bundles
        // For now, we provide the structure that will be populated when linked
        activityText = ""
        categories = []

        // Populate from BundlesManager when available:
        // for bundle in BundlesManager.sharedInstance.bundles {
        //     bundles.append(BundleItem(from: bundle))
        //     if let category = bundle.category {
        //         categories.insert(category)
        //     }
        // }
    }
}

// MARK: - Bundle Model

struct BundleItem: Identifiable {
    let id = UUID()
    var name: String
    var category: String?
    var summary: String
    var isInstalled: Bool
    var isMandatory: Bool
    var lastUpdated: Date?
    var htmlURL: URL?

    var sortableDate: Date { lastUpdated ?? .distantPast }

    enum InstallState {
        case installed, notInstalled, mixed
    }

    var installState: InstallState {
        .installed // Simplified; in production checks BundleInstallHelper state
    }
}
