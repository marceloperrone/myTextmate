import SwiftUI

// MARK: - Settings Store

/// Observable wrapper around SettingsBridge for SwiftUI bindings.
/// Routes keys to either NSUserDefaults or the C++ settings_t engine.
@Observable
public final class SettingsStore {
    public static let shared = SettingsStore()

    private init() {}

    // MARK: - UserDefaults Access

    public func bool(forDefaultsKey key: String) -> Bool {
        UserDefaults.standard.bool(forKey: key)
    }

    public func setBool(_ value: Bool, forDefaultsKey key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }

    public func string(forDefaultsKey key: String) -> String? {
        UserDefaults.standard.string(forKey: key)
    }

    public func setString(_ value: String?, forDefaultsKey key: String) {
        if let value {
            UserDefaults.standard.set(value, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    public func object(forDefaultsKey key: String) -> Any? {
        UserDefaults.standard.object(forKey: key)
    }

    public func setObject(_ value: Any?, forDefaultsKey key: String) {
        if let value {
            UserDefaults.standard.set(value, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    // MARK: - C++ Settings Access

    public func settingsValue(forKey key: String) -> String? {
        SettingsBridge.value(forSettingsKey: key) as? String
    }

    public func setSettingsValue(_ value: String?, forKey key: String) {
        SettingsBridge.setValue(value, forSettingsKey: key)
    }

    public func setSettingsValue(_ value: String, forKey key: String, scope: String) {
        SettingsBridge.setValue(value, forSettingsKey: key, scope: scope)
    }

    public func rawSettingsValue(forKey key: String, scope: String) -> String? {
        SettingsBridge.rawValue(forSettingsKey: key, scope: scope)
    }

    // MARK: - SwiftUI Bindings

    public func defaultsBinding(forKey key: String) -> Binding<Bool> {
        Binding(
            get: { self.bool(forDefaultsKey: key) },
            set: { self.setBool($0, forDefaultsKey: key) }
        )
    }

    public func negatedDefaultsBinding(forKey key: String) -> Binding<Bool> {
        Binding(
            get: { !self.bool(forDefaultsKey: key) },
            set: { self.setBool(!$0, forDefaultsKey: key) }
        )
    }

    public func stringDefaultsBinding(forKey key: String) -> Binding<String> {
        Binding(
            get: { self.string(forDefaultsKey: key) ?? "" },
            set: { self.setString($0, forDefaultsKey: key) }
        )
    }

    public func settingsBinding(forKey key: String) -> Binding<String> {
        Binding(
            get: { self.settingsValue(forKey: key) ?? "" },
            set: { self.setSettingsValue($0, forKey: key) }
        )
    }
}

// MARK: - UserDefaults Keys

public enum DefaultsKey {
    // Files
    public static let disableSessionRestore = "disableSessionRestore"
    public static let disableNewDocumentAtStartup = "disableNewDocumentAtStartup"
    public static let disableNewDocumentAtReactivation = "disableNewDocumentAtReactivation"

    // Projects
    public static let foldersOnTop = "foldersOnTop"
    public static let showFileExtensions = "showFileExtensions"
    public static let initialFileBrowserURL = "initialFileBrowserURL"
    public static let fileBrowserPlacement = "fileBrowserPlacement"
    public static let fileBrowserSingleClickToOpen = "fileBrowserSingleClickToOpen"
    public static let fileBrowserStyle = "fileBrowserStyle"
    public static let htmlOutputPlacement = "htmlOutputPlacement"
    public static let disableFileBrowserWindowResize = "disableFileBrowserWindowResize"
    public static let autoRevealFile = "autoRevealFile"
    public static let allowExpandingLinks = "allowExpandingLinks"
    public static let disableTabReordering = "disableTabReordering"
    public static let disableTabAutoClose = "disableTabAutoClose"
    public static let disableTabBarCollapsing = "disableTabBarCollapsing"

    // Bundles
    public static let disableBundleUpdates = "disableBundleUpdates"

    // Appearance
    public static let disableAntiAlias = "disableAntiAlias"
    public static let lineNumbers = "lineNumbers"

    // Other
    public static let disableCrashReporting = "DisableCrashReports"
    public static let crashReportsContactInfo = "CrashReportsContactInfo"
}
