import SwiftUI

// MARK: - Settings Window

/// Main preferences window replacing Preferences.mm + OakTransitionViewController.
/// Uses TabView with .sidebarAdaptable style on macOS 14+, or toolbar tabs on macOS 13.
public struct SettingsWindow: View {
    @AppStorage("MASPreferences Selected Identifier View")
    private var selectedTab: SettingsTab = .files

    public init() {}

    public var body: some View {
        TabView(selection: $selectedTab) {
            FilesSettingsView()
                .tabItem { Label("Files", systemImage: "doc.on.doc") }
                .tag(SettingsTab.files)

            ProjectsSettingsView()
                .tabItem { Label("Projects", systemImage: "folder") }
                .tag(SettingsTab.projects)

            BundlesSettingsView()
                .tabItem { Label("Bundles", systemImage: "shippingbox") }
                .tag(SettingsTab.bundles)
        }
        .frame(minWidth: 622)
    }
}

public enum SettingsTab: String, CaseIterable {
    case files = "Files"
    case projects = "Projects"
    case bundles = "Bundles"
}

// MARK: - NSWindowController Wrapper

/// Drop-in replacement for the ObjC Preferences class.
/// Usage: SettingsWindowController.shared.showWindow(nil)
@objc(SettingsWindowController)
public final class SettingsWindowController: NSWindowController {
    @objc public static let shared = SettingsWindowController()

    private init() {
        let hostingController = NSHostingController(rootView: SettingsWindow())
        let window = NSPanel(contentViewController: hostingController)
        window.title = "Settings"
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.hidesOnDeactivate = false

        if #available(macOS 11.0, *) {
            window.toolbarStyle = .preference
        }

        // Restore window position
        if let topLeft = UserDefaults.standard.string(forKey: "MASPreferences Frame Top Left") {
            window.setFrameTopLeftPoint(NSPointFromString(topLeft))
        }

        super.init(window: window)

        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: window,
            queue: .main
        ) { [weak window] _ in
            guard let window else { return }
            let topLeft = NSPoint(x: window.frame.minX, y: window.frame.maxY)
            UserDefaults.standard.set(NSStringFromPoint(topLeft), forKey: "MASPreferences Frame Top Left")
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}
