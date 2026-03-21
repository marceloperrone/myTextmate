import SwiftUI

@main
struct TextMateApp: App {
    @NSApplicationDelegateAdaptor(AppController.self) var appController

    init() {
        // Ignore signals — dispatch sources handle them on the main queue
        signal(SIGINT, SIG_IGN)
        signal(SIGTERM, SIG_IGN)
        signal(SIGPIPE, SIG_IGN)

        setupSignalSources()
        cleanEnvironment()
    }

    var body: some Scene {
        Settings {
            EmptyView() // Preferences handled by SettingsWindowController
        }
    }

    // MARK: - Signal Handling

    private func setupSignalSources() {
        // SIGTERM: quick shutdown — save session and stop
        let sigTermSrc = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        sigTermSrc.setEventHandler {
            DocumentWindowController.saveSession(includingUntitledDocuments: true)
            NotificationCenter.default.post(name: NSApplication.willTerminateNotification, object: NSApp)
            NSApp.stop(nil)
            if let event = NSEvent.otherEvent(
                with: .applicationDefined, location: .zero, modifierFlags: [],
                timestamp: 0, windowNumber: 0, context: nil,
                subtype: 0, data1: 0, data2: 0)
            {
                NSApp.postEvent(event, atStart: false)
            }
            UserDefaults.standard.synchronize()
        }
        sigTermSrc.resume()

        // SIGINT: regular shutdown
        let sigIntSrc = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        sigIntSrc.setEventHandler {
            NSApp.terminate(nil)
        }
        sigIntSrc.resume()

        // Prevent deallocation by storing in static vars
        Self._sigTermSource = sigTermSrc
        Self._sigIntSource = sigIntSrc
    }

    private func cleanEnvironment() {
        for key in ProcessInfo.processInfo.environment.keys where key.hasPrefix("TM_") {
            unsetenv(key)
        }
    }

    // Hold references to prevent deallocation
    private static var _sigTermSource: Any?
    private static var _sigIntSource: Any?
}
