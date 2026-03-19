// TextMateUI — SwiftUI replacement for TextMate's UI components
//
// This package provides SwiftUI implementations of 4 TextMate UI components:
//
// Phase 1: Preferences Window (SettingsWindow)
//   - FilesSettingsView, ProjectsSettingsView, BundlesSettingsView
//   - VariablesSettingsView, UpdateSettingsView, TerminalSettingsView
//
// Phase 2: Status Bar (StatusBarView + StatusBarViewModel)
//
// Phase 3: Tab Bar (TabBarView + TabBarModel + TabBarLayout)
//
// Phase 4: File Browser (FileBrowserView + FileTreeModel + NavigationModel)
//
// Integration:
//   Each component provides an NSView/NSViewController factory function
//   for embedding in the existing AppKit-based DocumentWindowController.

import SwiftUI

// MARK: - Version

public enum TextMateUIVersion {
    public static let major = 1
    public static let minor = 0
    public static let patch = 0
    public static var string: String { "\(major).\(minor).\(patch)" }
}
