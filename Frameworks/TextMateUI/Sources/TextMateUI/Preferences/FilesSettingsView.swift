import SwiftUI

// MARK: - Files Preferences Pane

/// Replaces FilesPreferences.mm — session restore, new document type, encoding, line endings.
public struct FilesSettingsView: View {
    @State private var settings = SettingsStore.shared

    @AppStorage(DefaultsKey.disableSessionRestore)
    private var disableSessionRestore = false

    @AppStorage(DefaultsKey.disableNewDocumentAtStartup)
    private var disableNewDocumentAtStartup = false

    @AppStorage(DefaultsKey.disableNewDocumentAtReactivation)
    private var disableNewDocumentAtReactivation = false

    @State private var encoding: String = "UTF-8"
    @State private var lineEndings: LineEnding = .lf
    @State private var newDocumentType: String = "text.plain"
    @State private var unknownDocumentType: String = ""
    @State private var grammars: [GrammarItem] = []

    public init() {}

    public var body: some View {
        Form {
            Section("Startup") {
                Toggle("Open documents from last session", isOn: Binding(
                    get: { !disableSessionRestore },
                    set: { disableSessionRestore = !$0 }
                ))

                Text("Hold shift (\u{21E7}) to bypass")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 20)
            }

            Section("With no open documents") {
                Toggle("Create one at startup", isOn: Binding(
                    get: { !disableNewDocumentAtStartup },
                    set: { disableNewDocumentAtStartup = !$0 }
                ))

                Toggle("Create one when re-activated", isOn: Binding(
                    get: { !disableNewDocumentAtReactivation },
                    set: { disableNewDocumentAtReactivation = !$0 }
                ))
            }

            Section("Document Types") {
                Picker("New document type:", selection: $newDocumentType) {
                    ForEach(grammars, id: \.scopeName) { grammar in
                        Text(grammar.name).tag(grammar.scopeName)
                    }
                }
                .onChange(of: newDocumentType) { _, value in
                    settings.setSettingsValue(value, forKey: "fileType", scope: "attr.untitled")
                }

                Picker("Unknown document type:", selection: $unknownDocumentType) {
                    Text("Prompt for type").tag("")
                    Divider()
                    ForEach(grammars, id: \.scopeName) { grammar in
                        Text(grammar.name).tag(grammar.scopeName)
                    }
                }
                .onChange(of: unknownDocumentType) { _, value in
                    settings.setSettingsValue(value, forKey: "fileType", scope: "attr.file.unknown-type")
                }
            }

            Section("Encoding") {
                Picker("Encoding:", selection: $encoding) {
                    Text("UTF-8").tag("UTF-8")
                    Text("UTF-16").tag("UTF-16")
                    Text("UTF-16 BE").tag("UTF-16BE")
                    Text("UTF-16 LE").tag("UTF-16LE")
                    Divider()
                    Text("ISO 8859-1 (Latin 1)").tag("ISO-8859-1")
                    Text("ISO 8859-2 (Latin 2)").tag("ISO-8859-2")
                    Text("ISO 8859-15 (Latin 9)").tag("ISO-8859-15")
                    Text("Mac Roman").tag("MACROMAN")
                    Text("Windows 1252").tag("WINDOWS-1252")
                    Divider()
                    Text("Shift JIS").tag("SHIFT_JIS")
                    Text("EUC-JP").tag("EUC-JP")
                    Text("ISO 2022-JP").tag("ISO-2022-JP")
                    Text("EUC-KR").tag("EUC-KR")
                    Text("GB 18030").tag("GB18030")
                    Text("Big5").tag("BIG5")
                }
                .onChange(of: encoding) { _, value in
                    settings.setSettingsValue(value, forKey: "encoding")
                }

                Picker("Line endings:", selection: $lineEndings) {
                    Text("LF (recommended)").tag(LineEnding.lf)
                    Text("CR (Mac Classic)").tag(LineEnding.cr)
                    Text("CRLF (Windows)").tag(LineEnding.crlf)
                }
                .onChange(of: lineEndings) { _, value in
                    settings.setSettingsValue(value.rawValue, forKey: "lineEndings")
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: loadSettings)
    }

    private func loadSettings() {
        encoding = settings.settingsValue(forKey: "encoding") ?? "UTF-8"
        if let le = settings.settingsValue(forKey: "lineEndings") {
            lineEndings = LineEnding(rawValue: le) ?? .lf
        }
        newDocumentType = settings.rawSettingsValue(forKey: "fileType", scope: "attr.untitled") ?? "text.plain"
        unknownDocumentType = settings.rawSettingsValue(forKey: "fileType", scope: "attr.file.unknown-type") ?? ""

        let entries = BundlesBridge.availableGrammars()
        grammars = entries.compactMap { entry in
            guard !entry.hiddenFromUser else { return nil }
            return GrammarItem(name: entry.name, scopeName: entry.scopeName)
        }
    }
}

// MARK: - Supporting Types

enum LineEnding: String {
    case lf = "\\n"
    case cr = "\\r"
    case crlf = "\\r\\n"
}

struct GrammarItem: Identifiable {
    let name: String
    let scopeName: String
    var id: String { scopeName }
}
