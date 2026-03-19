# TextMate UI Modernization Plan

## Scope

Replace four self-contained UI components with SwiftUI or modern AppKit while keeping the C++ engine (buffer, layout, parse, scope, theme) completely untouched.

**Target components:**

| Component | Location | Lines of ObjC++ | Complexity |
|---|---|---|---|
| Preferences Window | `Frameworks/Preferences/` | ~1,919 | Low |
| Status Bar | `OakTextView/src/OTVStatusBar.mm` | ~339 | Low |
| Tab Bar | `Frameworks/OakTabBarView/` | ~1,604 | High |
| File Browser | `Frameworks/FileBrowser/` | ~4,838 | High |

**Total code to replace:** ~8,700 lines of Objective-C++

---

## Prerequisites

### P1. Swift–ObjC++ Bridging Header

Before touching any UI component, establish the project's Swift interop layer. The C++ engine communicates with the UI through Objective-C++ `.mm` files, so SwiftUI views need a clean path to read engine state and call engine methods.

**Work:**
- Create a Swift bridging header that exposes the necessary Objective-C protocols and types (`OakTabBarViewDataSource`, `FileBrowserDelegate`, `PreferencesPaneProtocol`, etc.)
- Wrap the `OakUIConstructionFunctions.h` utility types (these are used everywhere — `OakCreateLabel`, `OakCreatePopUpButton`, `OakCreateCheckBox`, `OakSetupGridViewWithSeparators`, etc.) as Swift equivalents or just stop using them in new code since SwiftUI has native alternatives for all of them
- Expose the `settings_t` C++ settings bridge through an Objective-C wrapper so SwiftUI views can read/write TextMate settings (the existing `PreferencesPane` already does this via `valueForUndefinedKey:` / `setValue:forUndefinedKey:` — extract that into a reusable `SettingsBridge` class)

**Deliverable:** A `TextMateUI` Swift package (or framework target) that can import the bridging header and produce `NSView`/`NSViewController` instances consumable by the existing `DocumentWindowController`.

**Estimated effort:** 3–5 days

### P2. Build System Updates

TextMate uses a custom `configure` script and `.rave` build files, not a standard Xcode project. Adding Swift compilation requires either:
- **Option A:** Generate an Xcode project (e.g., via CMake or manually) that includes both the existing C++/ObjC++ targets and new Swift targets
- **Option B:** Add Swift Package Manager targets for the new UI code and link them into the existing build

Option B is recommended — keep the existing build for the engine, add SPM packages for new Swift UI code, and link them in the final application target.

**Estimated effort:** 2–3 days

---

## Phase 1: Preferences Window

**Why start here:** Lowest risk. The preferences window is entirely independent — closing it has zero effect on the editor. Each pane is self-contained. There's no real-time data flow or animation. Perfect for learning the bridging patterns.

### Current Architecture

The preferences window is an `NSWindowController` managing an `NSPanel` with toolbar-based pane switching via `OakTransitionViewController`. There are 6 panes:

1. **Files** (142 lines) — Checkboxes, popups for default encoding, line endings, restore session. Binds to both `NSUserDefaults` and C++ `settings_t`.
2. **Projects** (202 lines) — File browser settings, tab behavior, glob patterns for filtering. All `NSUserDefaults` bindings.
3. **Bundles** (429 lines) — Table view listing installed bundles with search/filter, install/uninstall, category scope bar. Depends on `BundlesManager` framework.
4. **Variables** (184 lines) — Editable table of environment variables (name/value/enabled). Pure `NSUserDefaults`.
5. **Terminal** (369 lines) — `mate` CLI installation with privilege escalation. Only pane using a XIB (`TerminalPreferences.xib`). Depends on Authorization framework.
6. **Software Update** (174 lines) — Update channel, frequency, crash reporting. Depends on `SoftwareUpdate` framework.

### Plan

**Step 1.1 — Create `SettingsBridge` (shared utility)**

Extract the key-value bridging from `PreferencesPane.mm` into a standalone Objective-C class:

```
@interface SettingsBridge : NSObject
+ (id)valueForSettingsKey:(NSString*)key;
+ (void)setValue:(id)value forSettingsKey:(NSString*)key;
@end
```

This wraps the `settings_t::raw_get()` / `settings_t::raw_set()` calls and makes them callable from Swift. The `defaultsProperties` and `tmProperties` dictionaries from `PreferencesPane` define which keys route where — encode that mapping in `SettingsBridge`.

**Step 1.2 — Rewrite each pane as a SwiftUI View**

Start with the simplest panes and work up:

1. **Variables** → `VariablesSettingsView.swift` — A `List` with `TextField` rows and add/remove buttons. Reads/writes `kUserDefaultsEnvironmentVariablesKey` from `UserDefaults`. No C++ dependency.

2. **Software Update** → `UpdateSettingsView.swift` — Popups and checkboxes binding to `UserDefaults`. The "Check Now" button calls into `SoftwareUpdate` framework (expose via bridging header).

3. **Files** → `FilesSettingsView.swift` — Checkboxes and popups. Uses both `UserDefaults` and `SettingsBridge` for the C++ settings (encoding, line endings, default grammar).

4. **Projects** → `ProjectsSettingsView.swift` — Checkboxes, popups, and text fields for glob patterns. All `UserDefaults`.

5. **Terminal** → `TerminalSettingsView.swift` — The most complex individual pane because of privilege escalation for `mate` installation. Wrap the `install_mate()` / `uninstall_mate()` C functions in a Swift-callable Objective-C helper. The rmate configuration is just `UserDefaults` bindings.

6. **Bundles** → `BundlesSettingsView.swift` — The largest pane. Needs a `Table` or `List` with search field, scope bar (category filter), and mixed-state checkboxes. The data source is `BundlesManager` — expose its API through the bridging header. This pane has the most UI complexity (progress indicators, live status updates).

**Step 1.3 — Replace the Preferences window controller**

Replace `Preferences.mm` and `OakTransitionViewController` usage with a new `SettingsWindow.swift` that uses:
- `Settings` scene (macOS 14+) or `NSHostingController` wrapping a `TabView` with `.sidebarAdaptable` style
- Each tab hosts one of the SwiftUI pane views
- Window remembers selected pane via `@AppStorage`

The new window should use `NSWindowToolbarStylePreference` (the existing code already does this) and SF Symbols for toolbar icons (replacing the custom PNG icons in `Preferences/icons/`).

**Step 1.4 — Remove old code**

Delete `Preferences/src/*.mm`, `Preferences/src/*.h`, `Preferences/resources/`, and the XIB. Update the build to link the new Swift package instead.

### Risk Assessment

- **Low risk** — Preferences window has no effect on editor performance or document handling
- **Data migration:** None needed — the new views read the same `NSUserDefaults` keys and `settings_t` entries
- **Testing:** Open preferences, change every setting, verify it persists and takes effect in the editor
- **Rollback:** Keep old code on a branch; the bridging header doesn't modify any existing files

### Estimated Effort

- SettingsBridge + bridging: 2 days
- 6 panes in SwiftUI: 5–7 days (Variables/Update in 1 day, Files/Projects in 1 day, Terminal in 1 day, Bundles in 2–3 days)
- Window controller replacement: 1 day
- Testing and polish: 2 days
- **Total: ~10–12 days**

---

## Phase 2: Status Bar

**Why second:** Small, self-contained, and a highly visible visual improvement. The status bar is a single 339-line file (`OTVStatusBar.mm`) embedded in `OakDocumentView`.

### Current Architecture

`OTVStatusBar` is an `NSVisualEffectView` containing 6 elements laid out with visual format constraints:

```
[line info] [selection] | [grammar popup] | [tab size popup] | [bundle items] | [symbol popup] | [recording indicator]
```

It communicates with the editor through a delegate protocol:

```objc
@protocol OTVStatusBarDelegate
- (void)takeGrammarUUIDFrom:(id)sender;
- (void)takeTabSizeFrom:(id)sender;
- (void)takeSoftTabsFrom:(id)sender;
- (void)showSymbolSelector:(NSPopUpButton*)sender;
- (void)showBundleItemSelector:(NSPopUpButton*)sender;
- (void)takeThemeUUIDFrom:(id)sender;
- (void)toggleMacroRecording:(id)sender;
@end
```

Properties set by the document view controller: `grammarName`, `symbolName`, `selectionString`, `tabSize`, `softTabs`, `isMacroRecording`, `recordingTimer`.

### Plan

**Step 2.1 — Create `StatusBarView.swift`**

A SwiftUI view with an `HStack` of the same elements. Use `@Observable` or `@ObservedObject` with a view model that the existing `OakDocumentView` populates.

Key elements:
- `Text` for line/selection display
- `Menu` or `Picker` for grammar selection
- `Menu` for tab size (with soft tabs toggle)
- `Button` for bundle items (opens popup)
- `Menu` for symbol navigation
- Recording indicator with animation

Use `NSHostingView` to embed in the existing `OakDocumentView` layout, replacing the old `OTVStatusBar` instance.

**Step 2.2 — Create `StatusBarViewModel`**

An `@Observable` class that conforms to a protocol the existing Objective-C code can update:

```swift
@Observable class StatusBarViewModel {
    var selectionString: String = ""
    var grammarName: String = ""
    var symbolName: String = ""
    var tabSize: Int = 4
    var softTabs: Bool = false
    var isMacroRecording: Bool = false
}
```

Expose this class to Objective-C via `@objc`. The existing `OakDocumentView.mm` creates the view model, passes it to the SwiftUI status bar, and updates properties as needed.

**Step 2.3 — Wire delegate callbacks**

The status bar actions (grammar change, tab size change, symbol selection) call back to the existing delegate. Route these through the view model → Objective-C delegate pattern.

**Step 2.4 — Visual improvements**

Now that it's SwiftUI, take the opportunity to:
- Use proper `controlGroup` styling
- Add subtle hover effects on interactive elements
- Use `monospacedDigit()` for the selection/line display
- Consider adding a file encoding indicator (currently missing)

### Risk Assessment

- **Medium-low risk** — The status bar touches the editor view hierarchy, but its data flow is one-directional (editor → status bar display, status bar actions → delegate callbacks)
- **Constraint:** The status bar must be an `NSView` (via `NSHostingView`) because `OakDocumentView` uses Auto Layout with `OakAddAutoLayoutViewsToSuperview`
- **Testing:** Verify all status bar items update correctly (selection changes, grammar switching, tab size, symbol navigation, macro recording toggle)

### Estimated Effort

- StatusBarView + ViewModel: 2 days
- Wiring into OakDocumentView: 1 day
- Polish and testing: 1 day
- **Total: ~4 days**

---

## Phase 3: Tab Bar

**Why third:** Higher complexity but very high visual payoff. The tab bar is the most prominent UI element after the editor itself.

### Current Architecture

`OakTabBarView` (1,369 lines) is a fully custom `NSView` that:
- Renders individual `OakTabView` subviews for each tab
- Implements a sophisticated responsive layout algorithm (fitting tabs to available width, overflow menu)
- Supports drag-and-drop between tab bars (including across windows)
- Uses `NSTitlebarAccessoryViewController` to sit in the window titlebar
- Has animated layout transitions with `CAAnimation`
- Manages close buttons with rollover behavior and modified-state indicators

`OakTabBarViewController` (235 lines) bridges the tab bar to the document management system via array properties (`identifiers`, `titles`, `modifiedStates`, `URLs`).

**Data source protocol:**
```objc
- numberOfRowsInTabBarView:
- tabBarView:titleForIndex:
- tabBarView:pathForIndex:
- tabBarView:UUIDForIndex:
- tabBarView:isEditedAtIndex:
```

**Delegate protocol (10 methods):** Selection validation, double-click handling, context menus, cross-tab-bar drag-drop, close actions.

### Plan

**Step 3.1 — Create `TabBarView.swift`**

This is the most architecturally challenging component because the tab bar must:
- Live in the titlebar (via `NSTitlebarAccessoryViewController`)
- Support drag-and-drop between windows
- Handle sophisticated responsive sizing
- Animate layout transitions smoothly

**Recommended approach:** Use SwiftUI for the individual tab rendering and layout logic, but keep the `NSTitlebarAccessoryViewController` wrapper in Objective-C (or use a thin Swift subclass). The tab bar needs `NSHostingView` inside the accessory view controller.

**Tab layout model:**
```swift
@Observable class TabBarModel {
    var tabs: [TabItem] = []
    var selectedIndex: Int = 0
    var visibleRange: Range<Int> = 0..<0
}

struct TabItem: Identifiable {
    let id: UUID
    var title: String
    var path: String
    var isModified: Bool
}
```

**Step 3.2 — Reimplement the layout algorithm in Swift**

Port the width-distribution logic from `makeLayoutForTabItems:inRectOfWidth:`. The current algorithm:
1. Computes each tab's ideal ("fitting") width based on title text
2. If total fits in available space, uses ideal widths (capped at 250px)
3. Otherwise, redistributes excess space from narrow tabs to wide ones using a supply/demand ratio
4. Clamps all tabs between 120px and 250px
5. If tabs still overflow, hides excess tabs and shows overflow menu on last visible tab

In SwiftUI, implement this as a custom `Layout` (iOS 16+ / macOS 13+) or use `GeometryReader` with calculated frames.

**Step 3.3 — Drag and drop**

This is the hardest part. The current implementation uses `NSDraggingSource` / `NSDraggingDestination` directly, with pasteboard serialization of `OakTabItem` (UUID, title, path, modified state). SwiftUI's `draggable()` / `dropDestination()` modifiers may not provide enough control for cross-window tab dragging.

**Recommended approach:** Use a hybrid — SwiftUI for rendering, but handle drag-and-drop at the `NSView` level via the `NSHostingView`'s underlying drag protocols. Create an `NSViewRepresentable` wrapper that adds dragging support.

**Step 3.4 — Animation**

The current code uses `CAAnimation` on a custom `tabLayoutAnimationProgress` property to interpolate between old and new tab layouts. In SwiftUI, use `withAnimation` and `matchedGeometryEffect` for tab reordering, `.transition()` for tab addition/removal.

**Step 3.5 — Integration**

Replace the `OakTabBarView` creation in `DocumentWindowController.mm` (around line 190) with the new SwiftUI-based tab bar. The `OakTabBarViewController` bridge class can be rewritten in Swift, still conforming to the same data source patterns expected by `DocumentWindowController`.

### Risk Assessment

- **High risk** — The tab bar is tightly integrated with window management, document lifecycle, and cross-window drag-drop
- **Regression areas:** Tab ordering, drag-drop between windows, overflow menu, keyboard shortcuts (Cmd+1–9), state restoration, close button behavior
- **Recommendation:** Ship this behind a feature flag (`defaults write com.macromates.TextMate useNewTabBar -bool YES`) so it can be tested without affecting stable users
- **Fallback:** Keep the old `OakTabBarView` in the build as a fallback

### Estimated Effort

- Tab rendering and layout: 4–5 days
- Drag-and-drop (hardest part): 3–4 days
- Animation and transitions: 2 days
- Integration with DocumentWindowController: 2 days
- Testing and polish: 3 days
- **Total: ~14–16 days**

---

## Phase 4: File Browser

**Why last:** The largest and most complex component. Best tackled after the team is comfortable with the bridging patterns established in Phases 1–3.

### Current Architecture

The file browser is ~4,838 lines across 14 `.mm` files. It consists of:

**Data layer:**
- `FileItem` — Model for files/directories with lazy-loaded children, SCM status, Finder tags
- `FileItemObserver` / `FSEventsManager` — Real-time file system monitoring via macOS FSEvents
- `SCMManager` — Git/SVN status integration
- `KEventManager` — BSD kqueue monitoring for individual file changes

**View layer:**
- `FileBrowserViewController` (2,328 lines) — Main controller, `NSOutlineViewDataSource`, navigation history, state persistence
- `FileBrowserView` — Container view with header + outline view + action bar
- `FileBrowserOutlineView` — Custom `NSOutlineView` subclass
- `FileItemTableCellView` — Custom cells with icon, name, Finder tags, close button
- `OFBHeaderView` — Back/forward buttons and breadcrumb popup
- `OFBActionsView` — Bottom toolbar (new, reload, search, favorites, SCM, actions)

**File operations:**
- `FileBrowserDiskOperations` (530 lines) — Copy, move, duplicate, rename, trash, new file/folder with undo support

### Plan

**Step 4.1 — Keep the data layer in Objective-C++**

The `FSEventsManager`, `SCMManager`, `KEventManager`, and `FileItemObserver` classes are low-level system integrations that work well as-is. Don't rewrite them. Instead, create Swift-friendly wrappers:

```swift
@Observable class FileTreeModel {
    var rootItem: FileItemWrapper
    var expandedURLs: Set<URL> = []
    var selectedURLs: Set<URL> = []
}

class FileItemWrapper: Identifiable {
    let item: FileItem  // ObjC object
    var children: [FileItemWrapper]
    var displayName: String
    var isDirectory: Bool
    var scmStatus: SCMStatus
    var finderTags: [FinderTag]
}
```

The wrapper observes the underlying `FileItem` changes and publishes updates to SwiftUI.

**Step 4.2 — Replace the outline view with SwiftUI**

Use SwiftUI's `List` with `OutlineGroup` or `DisclosureGroup` for the tree structure. This gets you:
- Built-in expand/collapse animation
- Native selection handling
- Keyboard navigation
- Accessibility for free

```swift
struct FileBrowserView: View {
    @State var model: FileTreeModel

    var body: some View {
        List(selection: $model.selectedURLs) {
            OutlineGroup(model.rootItem.children, children: \.children) { item in
                FileItemRow(item: item)
            }
        }
    }
}
```

**Step 4.3 — Reimplement navigation**

The current file browser has back/forward history, breadcrumb navigation, and special locations (Computer, Home, Favorites, SCM root). Create a `NavigationModel`:

```swift
@Observable class NavigationModel {
    var currentURL: URL
    var history: [NavigationEntry] = []
    var historyIndex: Int = 0

    func goBack() { ... }
    func goForward() { ... }
    func goToParent() { ... }
}
```

The header bar becomes a SwiftUI `HStack` with back/forward buttons and a `Menu` for the breadcrumb path.

**Step 4.4 — File operations**

Wrap `FileBrowserDiskOperations` in a Swift-callable interface. The drag-and-drop for file moving and the context menu actions route through this wrapper. Keep the undo manager integration.

**Step 4.5 — Actions bar**

Replace `OFBActionsView` with a SwiftUI toolbar or `HStack` of buttons. Map each button to existing actions (create, reload, search, favorites, SCM, more).

**Step 4.6 — QuickLook integration**

The current code implements `QLPreviewPanelDataSource`. This needs to stay at the AppKit level — use an `NSViewControllerRepresentable` or coordinator pattern to manage the QuickLook panel from SwiftUI.

**Step 4.7 — Integration**

The file browser's view is inserted into `ProjectLayoutView` as an `NSView`. Replace it with an `NSHostingView` wrapping the new SwiftUI file browser. Update `ProjectLayoutView.mm` to use the new view (same Auto Layout constraints, just a different view instance).

The `FileBrowserDelegate` protocol (which `DocumentWindowController` implements) stays the same — the new SwiftUI file browser calls through to it for opening and closing files.

### Risk Assessment

- **Highest risk** — The file browser has real-time file system monitoring, complex state management, and direct file system operations
- **Regression areas:** File watching (must not miss changes), drag-drop file operations, SCM status display, expand/collapse state persistence, performance with large directories
- **Performance concern:** `NSOutlineView` is extremely optimized for large datasets (lazy cell reuse). SwiftUI `List` is good but may need profiling with directories containing thousands of files
- **Recommendation:** Implement the view layer in SwiftUI but keep the file system monitoring and disk operations in Objective-C++. Ship behind a feature flag.

### Estimated Effort

- FileItem Swift wrappers: 3 days
- File tree view (OutlineGroup): 4–5 days
- Navigation (history, breadcrumbs): 2 days
- File operations integration: 2 days
- Header + actions bar: 2 days
- Context menus + QuickLook: 2 days
- Integration with ProjectLayoutView: 1 day
- Testing and polish: 4 days
- **Total: ~20–22 days**

---

## Shared Work: OakAppKit Replacements

Many UI components depend on `OakAppKit` utility functions. These need Swift equivalents:

| OakAppKit function | SwiftUI replacement |
|---|---|
| `OakCreateLabel()` | `Text()` with modifiers |
| `OakCreateCheckBox()` | `Toggle()` |
| `OakCreatePopUpButton()` | `Picker()` or `Menu()` |
| `OakCreateButton()` | `Button()` |
| `OakCreateNSBoxSeparator()` | `Divider()` |
| `OakSetupGridViewWithSeparators()` | `Form()` or `Grid()` |
| `OakAddAutoLayoutViewsToSuperview()` | Not needed (SwiftUI layout) |
| `OakRolloverButton` | Custom `Button` with `.onHover` |
| `OakBackgroundFillView` | `Rectangle().fill()` |
| `OakStatusBarFont()` | `.font(.system(size: 11))` |

These don't need a separate phase — replace them as you encounter them in each phase.

---

## Timeline Summary

| Phase | Component | Effort | Dependencies |
|---|---|---|---|
| P | Prerequisites (bridging, build) | 5–8 days | None |
| 1 | Preferences Window | 10–12 days | Prerequisites |
| 2 | Status Bar | 4 days | Prerequisites |
| 3 | Tab Bar | 14–16 days | Prerequisites, learnings from Phase 1–2 |
| 4 | File Browser | 20–22 days | Prerequisites, learnings from Phase 1–3 |

**Total: ~53–62 working days** (roughly 11–13 weeks for a single developer)

Phases 1 and 2 can run in parallel if two developers are available. Phase 3 and 4 benefit from the patterns established in earlier phases.

## Minimum macOS Target

SwiftUI features used in this plan require **macOS 13 (Ventura)** minimum:
- `Layout` protocol for custom tab sizing
- `OutlineGroup` for file browser tree
- `Table` for bundles preference pane
- Modern `Menu` and `Picker` APIs

If supporting macOS 12 is required, fall back to `NSHostingView` wrapping simpler SwiftUI views and keep more AppKit for the complex components (particularly the file browser outline).

## What NOT to Touch

This plan explicitly leaves the following untouched:
- `Frameworks/buffer/` — B-tree text storage
- `Frameworks/layout/` — CoreText rendering engine
- `Frameworks/parse/` — TextMate grammar parser
- `Frameworks/scope/` — Scope matching
- `Frameworks/theme/` — Theme resolution
- `Frameworks/editor/` — Editor commands
- `Frameworks/OakTextView/src/OakTextView.mm` — The text editor view itself
- `Frameworks/OakTextView/src/GutterView.mm` — Line numbers and folding
- `DocumentWindowController.mm` — Modified only at integration points, not rewritten
