# myTextmate

A fork of [TextMate](https://github.com/textmate/textmate), the macOS text editor, undergoing active modernization to bring its UI to macOS Tahoe (26) and SwiftUI while preserving the battle-tested C++ editing engine.

**Repository**: https://github.com/marceloperrone/myTextmate

---

## Architecture Overview

The app is a three-layer hybrid:

```
┌─────────────────────────────────────────────────┐
│  SwiftUI Views (TextMateUI)                     │  ← NEW (macOS 26+)
│  TabBar, StatusBar, FileBrowser, Preferences    │
├─────────────────────────────────────────────────┤
│  Objective-C++ Coordination Layer               │  ← LEGACY (being thinned)
│  DocumentWindowController, AppController,       │
│  OakTextView, OakDocument                       │
├─────────────────────────────────────────────────┤
│  C++ Core Engine (ng:: namespace)               │  ← STABLE (do not touch)
│  buffer_t, editor_t, parse, scope, bundles,     │
│  settings, regexp (Onigmo), layout              │
└─────────────────────────────────────────────────┘
```

**Integration pattern**: SwiftUI models are `@Observable` classes with `@objc` class names. ObjC instantiates them via `NSClassFromString()` and communicates through KVC (`setValue:forKey:`) and delegate selectors. SwiftUI views are embedded in AppKit via `NSHostingView`.

---

## What's Modern (Swift/SwiftUI)

All located in `Frameworks/TextMateUI/`:

| Component | Files | Status |
|-----------|-------|--------|
| **TabBar** | `TabBarModel.swift`, `TabBarView.swift`, `TabBarLayout.swift` | Integrated — lives in titlebar accessory |
| **StatusBar** | `StatusBarViewModel.swift`, `StatusBarView.swift` | Integrated — reads editor state from DocumentModel |
| **FileBrowser** | `FileTreeModel.swift`, `FileBrowserView.swift`, `FileItemRow.swift`, `NavigationModel.swift`, `FileBrowserHeaderView.swift` | Integrated — NavigationSplitView sidebar |
| **Document Split** | `DocumentSplitModel.swift`, `DocumentSplitView.swift` | Integrated — top-level container |
| **Preferences** | `SettingsWindow.swift`, `FilesSettingsView.swift`, `ProjectsSettingsView.swift`, `BundlesSettingsView.swift` | Integrated — replaces AppKit prefs panes |
| **FindBar** | `FindBarModel.swift`, `FindBarView.swift` | Integrated — inline find/replace in OakDocumentView |
| **FindPanel** | `FindPanelModel.swift`, `FindPanelView.swift` | Integrated — project/folder/open-files search panel |
| **About** | `AboutWindowController.swift` | Integrated — replaces AppKit AboutWindowController |
| **Document** | `DocumentModel.swift` | Integrated — reactive mirror of OakDocument/OakTextView state |
| **Bridge** | `SettingsStore.swift`, `HostingSupport.swift` | Shared infrastructure |
| **ObjC Bridge** | `TextMateBridge/` (`SettingsBridge.mm`, `BundlesBridge.mm`) | SPM stubs return mock data for previews; rave build uses real C++ implementations in `Frameworks/TextMateBridge/src/` |
| **App Entry** | `TextMateApp.swift` (in `Applications/TextMate/src/`) | `@main` struct with `@NSApplicationDelegateAdaptor(AppController.self)`, signal handling |

**Swift Package**: `Frameworks/TextMateUI/Package.swift` — Swift 5.9, macOS 26+, two targets: `TextMateBridge` (ObjC++) and `TextMateUI` (Swift).

**Key patterns used**:
- `@MainActor @Observable` models with `@ObservationIgnored` for ObjC interop properties
- `NSHostingView` / `NSHostingController` for embedding in AppKit
- `NSViewRepresentable` for wrapping remaining AppKit controls (NSPopUpButton)
- Custom `Layout` protocol for tab width algorithm
- Weak delegate/target references to prevent retain cycles
- `@AppStorage` for UserDefaults, `SettingsStore` for C++ settings bridge

---

## What's Legacy (Objective-C++ / C++)

### Core Editor Engine (C++ — STABLE, DO NOT MODIFY without deep understanding)

| Framework | Purpose | Key Types |
|-----------|---------|-----------|
| `buffer/` | Text buffer, syntax parsing, marks, symbols, spelling | `ng::buffer_t`, `ng::pairs_t` |
| `editor/` | All editing operations (66KB of logic) | `ng::editor_t`, `ng::action_t` |
| `selection/` | Selection management, column selection | `ng::range_t`, `ng::index_t` |
| `layout/` | Text layout and wrapping | Layout engine |
| `parse/` | Grammar parsing | Parser state machine |
| `scope/` | Scope context evaluation | `scope::context_t` |
| `bundles/` | .tmbundle loading, macro system | `bundles::item_ptr` |
| `settings/` | .tm_properties cascade | `settings_t` |
| `regexp/` | Regular expressions via Onigmo | Regex engine |
| `text/` | UTF-8 handling, case, newlines | Text utilities |
| `undo/` | Undo/redo stack | Undo manager |
| `command/` | Bundle command execution | Command runner |
| `theme/` | Syntax theme rendering | Theme engine |
| `plist/` | Property list parsing (Cap'n Proto) | Plist reader |

### ObjC++ UI & Coordination (LEGACY — migration targets)

| Framework/File | Purpose | Modernization Status |
|----------------|---------|---------------------|
| `DocumentWindowController.mm` (~1,600 lines + 10 category files) | Main window orchestration | Partially modernized — delegates to SwiftUI models, split into categories |
| `AppController.mm` (~830 lines) | App lifecycle, menus | Partially modernized — `@NSApplicationDelegateAdaptor` via `TextMateApp.swift` |
| `OakTextView/` | Core text editing NSView | Legacy — keep as-is (tightly coupled to C++ engine) |
| `OakDocument` | Document model wrapper | Legacy — keep as-is (bridges to ng::buffer_t) |
| `OakAppKit/` | AppKit utilities, extensions | Legacy — gradual replacement |
| `OakFilterList/` | Chooser dialogs (Open Quickly, etc.) | Legacy — migration candidate |
| `OakCommand/` | Command execution UI | Legacy — simplified (HTMLOutput removed) |
| `Find/` | Find & Replace panel | Partially modernized — SwiftUI form, AppKit results/status |
| `BundleEditor/` | Bundle editor window | Legacy — migration candidate |
| `MenuBuilder/` | Dynamic menu construction | Legacy — keep (works well) |
| `FileBrowser/` | ObjC file browser support code | Mostly replaced by SwiftUI |
| `OakTabBarView/` | Legacy tab bar | Replaced by SwiftUI (kept for header refs) |

### Already Removed

- `scm/` — Git/Hg/SVN/P4 integration (commit e7aac0ac)
- `HTMLOutput/`, `HTMLOutputWindow/` — HTML preview rendering
- `RMateServer` — Remote editing protocol
- `OTVStatusBar` — Old AppKit status bar
- Legacy Preferences panes (Terminal, Variables, SoftwareUpdate)
- `Shared/include/oak/sdk-compat.h` — Compatibility shims for macOS 10.13/10.14/11.0 (removed in Phase 0)
- `Applications/TextMate/src/main.mm` — C++ entry point, replaced by `@main` Swift `TextMateApp` struct (Phase 3)
- `Applications/TextMate/resources/English.lproj/MainMenu.xib` — Only contained delegate wiring + stale GoToLine panel (Phase 3)

---

## How Legacy and Modern Code Integrate

### Instantiation Flow (ObjC → Swift)
```objc
// DocumentWindowController.mm
Class TabBarModelClass = NSClassFromString(@"TabBarModel");
self.tabBarModel = [[TabBarModelClass alloc] init];
[self.tabBarModel setValue:self forKey:@"delegate"];
[self.tabBarModel setValue:self forKey:@"target"];
```

### Data Flow (ObjC → Swift model → SwiftUI view)
```objc
// ObjC pushes data into Swift @Observable model
[self.tabBarModel reloadWithCount:titles:paths:identifiers:editedFlags:];
// SwiftUI automatically re-renders via @Observable
```

### Action Flow (SwiftUI → ObjC via delegate)
```swift
// Swift model dispatches to ObjC delegate
_ = target?.perform(NSSelectorFromString("selectTab:"), with: NSNumber(value: index))
```

### View Embedding
```objc
// NSHostingView wraps SwiftUI view into AppKit hierarchy
NSView* hostingView = [self.splitModel valueForKey:@"hostingView"];
[self.window.contentView addSubview:hostingView];
```

### Forward Declarations (avoid import issues)
```objc
@interface NSObject (TabBarModelMethods)
- (void)reloadWithCount:(NSUInteger)count titles:(NSArray*)t ...;
@end
```

---

## Build System

**Tool**: Custom RAVE build system (`bin/rave`, Ruby) → generates `build.ninja` → executed by Ninja.

### Build & Run
```bash
./configure          # Validates dependencies, writes local.rave
ninja TextMate/run   # Build and launch (debug config)
ninja -f build.ninja TextMate/run  # Explicit
```

### Dependencies (install via Homebrew)
```
boost, capnp, google-sparsehash, multimarkdown, ninja, ragel
```

### Vendored Libraries
- **Onigmo** (`vendor/Onigmo/`) — Regex engine
- **kvdb** (`vendor/kvdb/`) — SQLite key-value store

### Key Build Settings
- Deployment target: macOS 26.0 (Tahoe) — set in `default.rave` `APP_MIN_OS`
- C++: C++2a, ObjC: ARC enabled
- Swift target: derived from `APP_MIN_OS` in `bin/rave`
- Debug: AddressSanitizer, Release: LTO + dead stripping
- Code signing: ad-hoc (`-`)

### Framework Count: ~49 frameworks, 11 applications/tools

---

## Project Structure

```
Applications/
  TextMate/          Main editor app (depends on 21 frameworks)
  mate/              CLI tool to open files
  SyntaxMate/        Syntax bundle manager
  QuickLookGenerator/ Quick Look plugin
  ...other CLI tools (bl, gtm, indent, tm_query, pretty_plist)

Frameworks/
  TextMateUI/        NEW — SwiftUI views + TextMateBridge (SPM package)
  TextMateBridge/    NEW — ObjC++ bridge exposing C++ to Swift
  DocumentWindow/    Main window controller (largest file: ~1500 lines .mm)
  OakTextView/       Core text editor NSView
  buffer/            C++ text buffer
  editor/            C++ editing operations
  OakAppKit/         AppKit extensions
  bundles/           Bundle system
  settings/          .tm_properties
  ...44 more frameworks

Shared/              Shared headers and precompiled headers
vendor/              Onigmo regex engine, kvdb
bin/                 Build scripts (rave)
```


## Modernization Plan: macOS Tahoe

### Phase 0: Foundation ✅ COMPLETE

- [x] **Bump deployment target** to macOS 26.0 (Tahoe)
  - `APP_MIN_OS` → `"26.0"` in `default.rave`, `.macOS(.v26)` in `Package.swift`
  - Fixed `bin/rave` to derive Swift `-target` from `APP_MIN_OS` (was hardcoded to `macos14.0`)
- [x] **Remove all compatibility code**
  - Deleted `Shared/include/oak/sdk-compat.h` and its PCH import
  - Removed ~30 `@available`/`#available` guards across 20+ ObjC/Swift files
  - Removed dead `NSUserNotification` code from CrashReporter
  - Removed `respondsToSelector:` version-gating (Touch Bar API guard in AppController)
- [x] **Adopt `@MainActor` on Swift models** — `TabBarModel`, `StatusBarViewModel`, `FileTreeModel`, `NavigationModel`, `DocumentSplitModel`, `SettingsStore`
  - Converted GCD dispatch in `FileTreeModel.loadDirectory()` to `Task.detached` + `MainActor.run`
  - Added `@MainActor` to `Coordinator` classes in `StatusBarView.swift`
- [x] **Update SPM bridge stubs** with mock data for SwiftUI previews (settings defaults + 12 grammar entries)
- **Note**: TextMateBridge C++ stubs (in SPM) remain stubs — the rave build uses the real implementations in `Frameworks/TextMateBridge/src/`

### Phase 1: Window Chrome ✅ COMPLETE

- [x] **Toolbar modernization** — `NSToolbar` with `NSWindowToolbarStyleUnified`, sidebar toggle + tracking separator, full `NSToolbarDelegate` in DocumentWindowController
- [x] **Liquid Glass** — `.glassEffect(.regular)` applied to TabBar, StatusBar, FileBrowserHeader, SettingsWindow, FindBar, FindPanel; `.glassEffect(.regular.interactive())` on selected tabs with `GlassEffectContainer`
- [x] **Tab bar refinement** — kept custom SwiftUI tabs with Tahoe glass styling (decided against `NSTabGroup`)
- [x] **Window style** — `NSWindowToolbarStyleUnified` + `NSWindowStyleMaskFullSizeContentView` for native Tahoe chrome

### Phase 2: Panels & Dialogs — NEARLY COMPLETE

- [x] **Find & Replace (inline)** — SwiftUI `FindBarModel` + `FindBarView` with glass effect, integrated in `OakDocumentView` via `NSClassFromString`. Supports find/replace fields, match counter, regex/case/wrap options, prev/next navigation, replace one/all.
- [x] **Find & Replace (project search)** — SwiftUI `FindPanelModel` + `FindPanelView` with glass effect, integrated in `Find.mm` via `NSClassFromString`. Search form (find/replace fields, options checkboxes, where popup, glob pattern) is SwiftUI; results tree (`FFResultsViewController`) and status bar (`FFStatusBarViewController`) preserved as `NSViewRepresentable` pass-throughs. `FFTextFieldViewController` no longer used by Find.mm.
- [x] **Open Quickly** — removed from menus; FileChooser import removed from DocumentWindowController. `OakFilterList/` framework still present (BundleItemChooser still active).
- [ ] **Bundle Editor** — `BundleEditor.mm` (1,051 lines) still pure AppKit with NSBrowser + OakDocumentView + PropertiesViewController.
- [x] **Go To Line** — removed from menus and AppController (IBOutlets, actions, menu validation all deleted). Feature removed.
- [x] **Symbol Chooser** — removed from OakDocumentView (import, property, setter, actions, delegate callbacks all deleted). Status bar symbol dropdown (`SymbolPopUpView`) still available in SwiftUI StatusBar.

### Phase 3: Reduce ObjC++ Coordination Layer — NEARLY COMPLETE

- [x] **Split DocumentWindowController** — reduced from 2,619 to ~1,600 lines by extracting self-contained sections into ObjC++ category files:
  - `DocumentWindowController+Private.h` — shared class extension, static helpers (`AllControllers`, `SortedControllers`, `is_disposable`), internal method declarations
  - `DocumentWindowController+TouchBar.mm` (~100 lines) — Touch Bar creation, item factory, navigation control
  - `DocumentWindowController+Session.mm` (~229 lines) — `+initialize`, session backup timer, save/restore, `setupControllerForProject:`, `-variables`
  - `OakDocumentController+DocumentWindow.mm` (~248 lines) — window routing (`findOrCreateController`, `showDocument`, `showDocuments`, `showFileBrowserAtPath`), `+controllerForDocument:`, `-bringToFront`
  - `DocumentWindowController+ScopeAttributes.mm` (~120 lines) — `updateExternalAttributes`, `setProjectPath:`, `setDocumentPath:`, `scopeAttributes`
  - `DocumentWindowController+CloseUI.mm` (~80 lines) — `saveAlertForDocuments:`, `showCloseWarningUIForDocuments:completionHandler:`, `windowShouldClose:`
  - `DocumentWindowController+TabContextMenu.mm` (~60 lines) — `tabBarModel:menuForIndex:` (context menu factory)
  - `DocumentWindowController+MenuValidation.mm` (~60 lines) — `validateMenuItem:` (NSMenuValidation)
  - `DocumentWindowController+TabDragDrop.mm` (~50 lines) — `performDropOfTabItem:atIndex:operation:`, `selectNextTab:`, `selectPreviousTab:`, `takeSelectedTabIndexFrom:`
  - `DocumentWindowController+ShowTabsMenu.mm` (~45 lines) — `updateShowTabMenu:` (Window > Show Tab submenu delegate)
- [x] **Consolidate StatusBarViewModel into DocumentModel** — removed 6 duplicate stored properties (`selectionString`, `symbolName`, `fileType`, `grammarName`, `tabSize`, `softTabs`) from StatusBarViewModel. It now holds a `documentModel` reference and reads via computed properties. OakDocumentView.mm pushes state to DocumentModel only, eliminating duplicate KVC pushes.
- [x] **AppController → @main SwiftUI App** — replaced `NSApplicationMain()` + `MainMenu.xib` with Swift `@main` `TextMateApp` struct using `@NSApplicationDelegateAdaptor(AppController.self)`. Signal handlers (SIGINT/SIGTERM) moved to Swift `DispatchSource`. C++ init (`oak::application_t::set_support`, `increase_max_open_files`) moved to `applicationWillFinishLaunching:`. XIB deleted (only contained delegate wiring + stale GoToLine panel). `AppController.h` cleaned for Swift import (C++ ivars moved to `AppController+Private.h`).
- [ ] **Menu system** — entirely MenuBuilder (ObjC++). No SwiftUI `CommandMenu`/`Commands`. MenuBuilder is well-suited for dynamic bundle menus and may intentionally stay as-is.


### Phase 4: Editor View Integration — PARTIALLY STARTED

- [ ] **OakTextView wrapper** — currently embedded via generic `AppKitViewRepresentable` (any NSView). Needs a specialized `NSViewRepresentable` with proper bindings for editor state, selection, theme, etc. Partially addressed: reactive editor state is now exposed via `DocumentModel`.
- [x] **Document model** — `DocumentModel.swift` (`@MainActor @Observable @objc(DocumentModel)`) is the single source of truth for editor state. OakDocumentView.mm instantiates via `NSClassFromString` and pushes editor state (selection, symbol, fileType, grammar, tabSize, softTabs, themeUUID) to DocumentModel only. StatusBarViewModel holds a `documentModel` reference and reads from it via computed properties — no duplicate KVC pushes. DocumentWindowController.mm pushes document-level state (path, displayName, identifier, isDocumentEdited, isOnDisk) on document switch and KVO changes.
- [ ] **GutterView** — `GutterView.h/.mm` (573 lines) still exists in `OakTextView/` but functionally disabled in `OakDocumentView.mm` ("stripped for Tahoe compatibility"). Needs SwiftUI rebuild or reintegration.
  
  
### Phase 5: Cleanup

- [ ] **Remove dead frameworks** — any remaining code for features that were stripped (SCM stubs, HTMLOutput refs)
- [ ] **Consolidate OakAppKit** — move still-needed utilities to Swift extensions, retire the framework
- [ ] **Remove OakTabBarView** — currently kept for header references only; fully decouple
- [ ] **Entitlements audit** — review if all entitlements are still needed

### Things to KEEP as-is

- **C++ engine** (`buffer/`, `editor/`, `parse/`, `scope/`, `selection/`, `layout/`, `undo/`) — this is TextMate's soul. It's stable, fast, and deeply interconnected. Rewriting it would be a multi-year effort with no user-facing benefit.
- **Bundle system** (`bundles/`, `command/`) — the .tmbundle ecosystem is a key differentiator
- **Settings cascade** (`settings/`) — .tm_properties is powerful and well-tested
- **Onigmo regex** — used throughout for syntax highlighting and find/replace
- **OakTextView** — tightly coupled to the C++ engine via `ng::editor_t`; wrap it, don't rewrite it


## Coding Conventions

- **C++**: `ng::` namespace, `snake_case`, `_t` suffix for types, `std::string` throughout
- **Objective-C++**: `.mm` extension, ARC enabled, properties for public API, delegate/target pattern
- **Swift**: `@MainActor @Observable` models, `@objc` class names for ObjC interop, weak delegate/target refs
- **SwiftUI**: `@ObservationIgnored` for non-reactive properties, lazy `NSHostingView` creation
- **Build**: Each framework has its own `default.rave` declaring dependencies
- **Interop**: `NSClassFromString()` + KVC for ObjC→Swift, `NSSelectorFromString()` for Swift→ObjC delegate calls

## Key Files

| File | Lines | Role |
|------|-------|------|
| `Frameworks/DocumentWindow/src/DocumentWindowController.mm` | ~1600 | Main window orchestration hub |
| `Frameworks/DocumentWindow/src/DocumentWindowController+Private.h` | ~120 | Private class extension, shared helpers |
| `Frameworks/DocumentWindow/src/DocumentWindowController+TouchBar.mm` | 100 | Touch Bar support |
| `Frameworks/DocumentWindow/src/DocumentWindowController+Session.mm` | 229 | Session save/restore, environment variables |
| `Frameworks/DocumentWindow/src/DocumentWindowController+ScopeAttributes.mm` | ~120 | Scope attribute discovery and setters |
| `Frameworks/DocumentWindow/src/DocumentWindowController+CloseUI.mm` | ~80 | Close warning dialogs, windowShouldClose |
| `Frameworks/DocumentWindow/src/DocumentWindowController+TabContextMenu.mm` | ~60 | Tab right-click context menu |
| `Frameworks/DocumentWindow/src/DocumentWindowController+MenuValidation.mm` | ~60 | NSMenuValidation |
| `Frameworks/DocumentWindow/src/DocumentWindowController+TabDragDrop.mm` | ~50 | Tab drag-drop and navigation |
| `Frameworks/DocumentWindow/src/DocumentWindowController+ShowTabsMenu.mm` | ~45 | Window > Show Tab submenu |
| `Frameworks/DocumentWindow/src/OakDocumentController+DocumentWindow.mm` | 248 | Window routing, document controller category |
| `Applications/TextMate/src/TextMateApp.swift` | ~65 | @main entry point, signal handling |
| `Applications/TextMate/src/AppController.mm` | ~830 | App delegate, menus, lifecycle |
| `Frameworks/OakTextView/src/OakTextView.mm` | Large | Core text editor view |
| `Frameworks/OakTextView/src/OakDocumentView.mm` | — | Wraps OakTextView + status bar |
| `Frameworks/editor/src/editor.cc` | 66KB | All editing operations |
| `Frameworks/buffer/src/buffer.cc` | 12KB | Text buffer implementation |
| `Frameworks/document/src/OakDocument.h` | 131 | Document model interface |
| `Frameworks/TextMateUI/Sources/TextMateUI/Document/DocumentModel.swift` | ~65 | Reactive document/editor state mirror |
| `Frameworks/TextMateUI/Sources/TextMateUI/` | ~25 files | All SwiftUI components |
| `Frameworks/TextMateUI/Sources/TextMateBridge/` | — | C++ ↔ Swift bridge |
| `default.rave` | 46 | Root build configuration |
