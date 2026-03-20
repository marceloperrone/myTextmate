import SwiftUI

// MARK: - About Window Controller

/// SwiftUI replacement for the ObjC AboutWindowController.
/// Instantiated from ObjC via NSClassFromString("AboutWindowModel").
@MainActor
@objc(AboutWindowModel)
public final class AboutWindowModel: NSObject {
    private var windowController: NSWindowController?

    @objc public static let sharedInstance = AboutWindowModel()

    @objc public func showAboutWindow(_ sender: Any?) {
        if let wc = windowController {
            wc.showWindow(sender)
            return
        }

        let view = AboutView()
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 340, height: 260)

        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 260),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.contentView = hostingView
        window.center()
        window.hidesOnDeactivate = false

        let wc = NSWindowController(window: window)
        windowController = wc
        wc.showWindow(sender)
    }

    public override init() {
        super.init()
    }
}

// MARK: - About View

private struct AboutView: View {
    private let version: String = {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
    }()

    private let copyright: String = {
        Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String ?? ""
    }()

    var body: some View {
        VStack(spacing: 12) {
            if let icon = NSApp.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 80, height: 80)
            }

            Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "TextMate")
                .font(.system(size: 20, weight: .semibold))

            Text("Version \(version)")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Text("Based on [TextMate](https://github.com/textmate/textmate) by Allan Odgaard")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Text("Licensed under the GNU General Public License v3")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)

            if !copyright.isEmpty {
                Text(copyright)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(24)
        .frame(width: 340, height: 260)
    }
}
