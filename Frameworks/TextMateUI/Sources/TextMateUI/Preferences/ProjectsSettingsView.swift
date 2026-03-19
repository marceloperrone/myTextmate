import SwiftUI

// MARK: - Projects Preferences Pane

/// Replaces ProjectsPreferences.mm — file browser settings, tab behavior, glob patterns.
public struct ProjectsSettingsView: View {
    private let settings = SettingsStore.shared

    @AppStorage(DefaultsKey.foldersOnTop)
    private var foldersOnTop = false

    @AppStorage(DefaultsKey.allowExpandingLinks)
    private var allowExpandingLinks = false

    @AppStorage(DefaultsKey.fileBrowserSingleClickToOpen)
    private var singleClickToOpen = false

    @AppStorage(DefaultsKey.autoRevealFile)
    private var autoRevealFile = false

    @AppStorage(DefaultsKey.fileBrowserPlacement)
    private var fileBrowserPlacement = "right"

    @AppStorage(DefaultsKey.disableFileBrowserWindowResize)
    private var disableAutoResize = false

    @AppStorage(DefaultsKey.disableTabBarCollapsing)
    private var disableTabBarCollapsing = false

    @AppStorage(DefaultsKey.disableTabReordering)
    private var disableTabReordering = false

    @AppStorage(DefaultsKey.disableTabAutoClose)
    private var disableTabAutoClose = false

    @AppStorage(DefaultsKey.htmlOutputPlacement)
    private var htmlOutputPlacement = "window"

    @State private var excludePattern = ""
    @State private var includePattern = ""
    @State private var binaryPattern = ""
    @State private var fileBrowserURL: URL?

    public init() {}

    public var body: some View {
        Form {
            Section("File Browser") {
                fileBrowserLocationPicker

                Toggle("Folders on top", isOn: $foldersOnTop)
                Toggle("Show links as expandable", isOn: $allowExpandingLinks)
                Toggle("Open files on single click", isOn: $singleClickToOpen)
                Toggle("Keep current document selected", isOn: $autoRevealFile)
            }

            Section("File Browser Position") {
                Picker("Show file browser on:", selection: $fileBrowserPlacement) {
                    Text("Left side").tag("left")
                    Text("Right side").tag("right")
                }

                Toggle("Adjust window when toggling display", isOn: Binding(
                    get: { !disableAutoResize },
                    set: { disableAutoResize = !$0 }
                ))
            }

            Section("Document Tabs") {
                Toggle("Show for single document", isOn: $disableTabBarCollapsing)

                Toggle("Re-order when opening a file", isOn: Binding(
                    get: { !disableTabReordering },
                    set: { disableTabReordering = !$0 }
                ))

                Toggle("Automatically close unused tabs", isOn: Binding(
                    get: { !disableTabAutoClose },
                    set: { disableTabAutoClose = !$0 }
                ))
            }

            Section("File Patterns") {
                TextField("Exclude files matching:", text: $excludePattern)
                    .onChange(of: excludePattern) { _, value in
                        settings.setSettingsValue(value, forKey: "excludeInFileChooser")
                    }

                TextField("Include files matching:", text: $includePattern)
                    .onChange(of: includePattern) { _, value in
                        settings.setSettingsValue(value, forKey: "includeFilesInFileChooser")
                    }

                TextField("Non-text files:", text: $binaryPattern)
                    .onChange(of: binaryPattern) { _, value in
                        settings.setSettingsValue(value, forKey: "binary")
                    }
            }

            Section("Command Output") {
                Picker("Show command output:", selection: $htmlOutputPlacement) {
                    Text("Below text view").tag("bottom")
                    Text("Right of text view").tag("right")
                    Text("New window").tag("window")
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: loadSettings)
    }

    private var fileBrowserLocationPicker: some View {
        Picker("File browser location:", selection: Binding(
            get: { fileBrowserURL ?? FileManager.default.homeDirectoryForCurrentUser },
            set: { url in
                fileBrowserURL = url
                UserDefaults.standard.set(url.absoluteString, forKey: DefaultsKey.initialFileBrowserURL)
            }
        )) {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first ?? home
            let root = URL(fileURLWithPath: "/")

            if let custom = fileBrowserURL, custom != desktop && custom != home && custom != root {
                Text(custom.lastPathComponent).tag(custom)
                Divider()
            }

            Text(FileManager.default.displayName(atPath: desktop.path)).tag(desktop)
            Text(FileManager.default.displayName(atPath: home.path)).tag(home)
            Text(FileManager.default.displayName(atPath: root.path)).tag(root)
        }
    }

    private func loadSettings() {
        excludePattern = settings.settingsValue(forKey: "excludeInFileChooser") ?? ""
        includePattern = settings.settingsValue(forKey: "includeFilesInFileChooser") ?? ""
        binaryPattern = settings.settingsValue(forKey: "binary") ?? ""

        if let urlString = UserDefaults.standard.string(forKey: DefaultsKey.initialFileBrowserURL) {
            fileBrowserURL = URL(string: urlString)
        }
    }
}
