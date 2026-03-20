import SwiftUI

// MARK: - Settings Window

/// Main preferences window replacing Preferences.mm + OakTransitionViewController.
public struct SettingsWindow: View {
    @AppStorage("MASPreferences Selected Identifier View")
    private var selectedTab: SettingsTab = .files

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Tab selector with glass effect
            Picker("", selection: $selectedTab) {
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 260)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(.clear)
            .glassEffect(.regular, in: .rect)

            // Pane content
            ScrollView {
                Group {
                    switch selectedTab {
                    case .files:
                        FilesSettingsView()
                    case .projects:
                        ProjectsSettingsView()
                    case .bundles:
                        BundlesSettingsView()
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 622, height: 560)
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
        hostingController.sizingOptions = [.preferredContentSize, .minSize]

        let window = NSPanel(contentViewController: hostingController)
        window.title = "Settings"
        window.setContentSize(NSSize(width: 622, height: 560))
        window.styleMask.remove(.resizable)
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.hidesOnDeactivate = false
        window.center()

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
