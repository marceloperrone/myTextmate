import SwiftUI

// MARK: - NSHostingView / NSHostingController Helpers

/// Creates an NSHostingView wrapping a SwiftUI view for embedding in AppKit layouts.
public func makeHostingView<Content: View>(_ view: Content) -> NSView {
    let hostingView = NSHostingView(rootView: view)
    hostingView.translatesAutoresizingMaskIntoConstraints = false
    return hostingView
}

/// Creates an NSHostingController wrapping a SwiftUI view.
public func makeHostingController<Content: View>(_ view: Content) -> NSHostingController<Content> {
    NSHostingController(rootView: view)
}

// MARK: - Window Helpers

/// Creates a preferences-style window with toolbar tab switching.
public func makePreferencesWindow(contentViewController: NSViewController) -> NSPanel {
    let window = NSPanel(contentViewController: contentViewController)
    window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
    window.hidesOnDeactivate = false
    window.toolbarStyle = .preference
    return window
}
