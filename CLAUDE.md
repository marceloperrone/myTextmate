# TextMate — SwiftUI Modernization

## What This Project Is

TextMate text editor. Objective-C++ codebase (~50 frameworks) with a custom build system. We are replacing the AppKit UI layer with SwiftUI while keeping the C++ engine untouched.

## CRITICAL: Do Not Touch the C++ Engine

The following frameworks are pure C++ and must never be modified:
`buffer`, `editor`, `encoding`, `layout`, `parse`, `scope`, `selection`, `text`, `theme`, `undo`

## Build System

### How to Build

```bash
./configure                    # First time only — checks deps, writes local.rave
bin/rave -cdebug -tTextMate    # Generates build.ninja (run from repo root)
ninja                          # Builds everything
```

The built app lands at: `~/build/myTextmate/debug/Applications/TextMate/TextMate.app`

For release: `bin/rave -crelease -tTextMate && ninja`

### How the Build System Works

- `bin/rave` is a ~1500-line Ruby script that reads `.rave` DSL files and generates `build.ninja`
- Every framework has a `default.rave` declaring its dependencies (`require`), sources, and frameworks
- The app target (`Applications/TextMate/default.rave`) pulls everything together via `require`
- `default.rave` at the repo root sets compiler flags and defines `debug`/`release` configs

### Key Idiosyncrasy: Link Rules

`bin/rave` detects Swift sources across the dependency graph. When any required target has `.swift` files:
- It uses `swiftc` (not `clang`) as the linker via a separate `LinkSwift` ninja rule
- It converts `-fsanitize=X` → `-sanitize=X` (swiftc format)
- It strips clang-only flags (`-mmacosx-version-min`, `-fobjc-link-runtime`, `-flto`)
- It converts `-Wl,flag` → `-Xlinker flag`
- It adds `-framework SwiftUI` automatically

**Bug we fixed:** Originally all executables shared one `rule Link` (using `clang`). When the TextMate app gained Swift dependencies, the flag transforms ran but the command was still `clang`. We split it into `rule Link` (clang) and `rule LinkSwift` (swiftc) — see `bin/rave` around line 1001.

### Dependency Management

Each `.rave` file declares `require OtherFramework` to depend on siblings. The app target's require list:
```
BundleEditor BundleMenu BundlesManager CommitWindow CrashReporter DocumentWindow Find
HTMLOutputWindow MenuBuilder OakAppKit OakCommand OakFilterList OakFoundation OakSystem
OakTextView Preferences SoftwareUpdate TextMateUI authorization bundles cf command crash
document io kvdb license network ns plist regexp scm settings text theme
```

## Architecture: ObjC ↔ SwiftUI Interop Pattern

All SwiftUI components follow the same pattern for integration with ObjC++:

### 1. Swift Model with `@objc(ClassName)`

```swift
@objc(StatusBarViewModel)    // ← Enables NSClassFromString("StatusBarViewModel")
@Observable
public final class StatusBarViewModel: NSObject {
    @objc public var selectionString: String = "1:1"  // ← KVC-settable from ObjC

    @ObservationIgnored
    @objc public weak var delegate: AnyObject?         // ← Weak ref to ObjC controller

    @ObservationIgnored
    @objc public weak var target: AnyObject?           // ← For selector dispatch

    @ObservationIgnored
    @objc public lazy var hostingView: NSView = {      // ← Factory, accessed via KVC
        NSHostingView(rootView: StatusBarView(model: self))
    }()

    // Actions dispatch to ObjC via selectors:
    public func selectGrammar(uuid: String) {
        let item = NSMenuItem()
        item.representedObject = uuid
        _ = target?.perform(NSSelectorFromString("takeGrammarUUIDFrom:"), with: item)
    }
}
```

### 2. ObjC Side Instantiates via Runtime

```objc
// In the .mm file — NO Swift imports needed:
Class Cls = NSClassFromString(@"StatusBarViewModel");
self.statusBarModel = [[Cls alloc] init];
[self.statusBarModel setValue:self forKey:@"delegate"];
[self.statusBarModel setValue:self forKey:@"target"];
NSView* hostingView = [self.statusBarModel valueForKey:@"hostingView"];
// Add hostingView to the AppKit view hierarchy
```

### 3. Forward-Declare Selectors

When calling methods with complex signatures on `id`, the compiler needs to see the selector. Add a category on NSObject:

```objc
@interface NSObject (TabBarModelMethods)
- (void)reloadWithCount:(NSInteger)count titles:(NSArray<NSString*>*)titles ...;
@end
```

### 4. Delegate Callbacks from Swift → ObjC

Swift model dispatches to ObjC delegate via `perform(_:with:)`:
```swift
_ = delegate?.perform(
    NSSelectorFromString("tabBarModel:didSelectIndex:"),
    with: self, with: NSNumber(value: index)
)
```

ObjC side implements the method normally:
```objc
- (void)tabBarModel:(id)model didSelectIndex:(NSNumber*)indexNumber {
    NSUInteger anIndex = indexNumber.unsignedIntegerValue;
    [self openAndSelectDocument:_documents[anIndex] activate:YES];
}
```

## TextMateUI Framework

Location: `Frameworks/TextMateUI/`

Has both a `Package.swift` (for standalone `swift build` testing) and a `default.rave` (for integration into the main build). The rave build is what matters for the actual app.

### default.rave
```
target "${dirname}" {
    require TextMateBridge
    sources Sources/TextMateUI/**/*.swift
    swift_bridging_header ${dir}/src/TextMateUI-Bridging-Header.h
    frameworks Cocoa SwiftUI
}
```

### Source Structure

```
Sources/TextMateUI/
├── TextMateUI.swift                 # Package entry
├── Preferences/                     # Phase 1: Settings window (6 panes)
│   ├── SettingsWindow.swift
│   ├── FilesSettingsView.swift
│   ├── ProjectsSettingsView.swift
│   ├── BundlesSettingsView.swift
│   ├── VariablesSettingsView.swift
│   ├── TerminalSettingsView.swift
│   └── UpdateSettingsView.swift
├── StatusBar/                       # Phase 2: Status bar (DONE — wired into OakDocumentView)
│   ├── StatusBarViewModel.swift
│   └── StatusBarView.swift
├── TabBar/                          # Phase 3: Tab bar (DONE — wired into DocumentWindowController)
│   ├── TabBarModel.swift
│   ├── TabBarView.swift
│   └── TabBarLayout.swift
├── FileBrowser/                     # Phase 4: File browser (DONE — NavigationSplitView sidebar)
│   ├── DocumentSplitModel.swift
│   ├── DocumentSplitView.swift
│   ├── FileBrowserView.swift
│   ├── FileTreeModel.swift
│   ├── NavigationModel.swift
│   ├── FileItemRow.swift
│   ├── FileBrowserHeaderView.swift
│   └── FileBrowserActionsView.swift
└── Shared/
    ├── HostingSupport.swift
    └── SettingsStore.swift
```

### TextMateBridge (ObjC bridge layer)

Location: `Frameworks/TextMateBridge/`

Provides ObjC classes that Swift can import via the bridging header. These are stubs that need C++ implementations wired in:
- `SettingsBridge` — reads/writes C++ settings engine
- `BundlesBridge` — queries bundle/grammar lists
- `SoftwareUpdateBridge` — update check state
- `MateInstallBridge` — `mate` CLI install status

Bridging header at `Frameworks/TextMateUI/src/TextMateUI-Bridging-Header.h`:
```objc
#import <TextMateBridge/SettingsBridge.h>
#import <TextMateBridge/BundlesBridge.h>
#import <TextMateBridge/SoftwareUpdateBridge.h>
#import <TextMateBridge/MateInstallBridge.h>
```

## Completed Integrations

### Status Bar (Phase 2)

- **Swift**: `StatusBarViewModel` + `StatusBarView`
- **ObjC**: `OakDocumentView.mm` instantiates via `NSClassFromString(@"StatusBarViewModel")`
- **Original**: `OTVStatusBar.mm` (still exists but bypassed)
- Properties set via KVC: `selectionString`, `grammarName`, `tabSize`, `softTabs`, etc.
- Actions dispatched via selectors: `takeGrammarUUIDFrom:`, `takeTabSizeFrom:`, etc.

### Tab Bar (Phase 3)

- **Swift**: `TabBarModel` + `TabBarView` + `TabBarLayout`
- **ObjC**: `DocumentWindowController.mm` instantiates via `NSClassFromString(@"TabBarModel")`
- **Original**: `OakTabBarView.mm` (still exists, no longer used by DocumentWindow)
- `DocumentWindow/default.rave` no longer requires `OakTabBarView`
- Titlebar accessory VC: `[tabBarModel valueForKey:@"titlebarViewController"]`
- Data reload: `[tabBarModel reloadWithCount:titles:paths:identifiers:editedFlags:]`
- Tab visibility: `[tabBarModel setValue:@(hidden) forKey:@"isHidden"]`
- Delegate methods: `tabBarModel:didSelectIndex:`, `tabBarModel:didDoubleClickIndex:`, `tabBarModelDidDoubleClickBackground:`, `tabBarModel:didCloseIndex:`, `tabBarModel:menuForIndex:`
- Context menu: returns NSMenu from `tabBarModel:menuForIndex:` — displayed via NSViewRepresentable overlay

### File Browser + NavigationSplitView (Phase 4)

- **Swift**: `DocumentSplitModel` + `DocumentSplitView` + `FileTreeModel` + `FileBrowserView`
- **ObjC**: `DocumentWindowController.mm` instantiates via `NSClassFromString(@"DocumentSplitModel")`
- **Architecture**: `NavigationSplitView` is the top-level window content, with sidebar=FileBrowserView, detail=NSViewRepresentable wrapping ProjectLayoutView
- `DocumentSplitModel` owns `FileTreeModel` and manages sidebar visibility
- `ProjectLayoutView` stripped of file browser code — now doc+html only
- Window style includes `NSWindowStyleMaskFullSizeContentView` for Liquid Glass on macOS Tahoe
- Sidebar visibility: `[splitModel setValue:@(visible) forKey:@"sidebarVisible"]`
- File browser access: `[splitModel valueForKey:@"fileBrowser"]` returns the FileTreeModel
- `fileBrowserOnRight` preference removed — NavigationSplitView sidebar is always on leading edge
- Window frame expand/shrink on toggle removed — NavigationSplitView handles sidebar slide in/out

### Key Files Modified

| File | What Changed |
|------|-------------|
| `Frameworks/DocumentWindow/src/DocumentWindowController.mm` | Uses DocumentSplitModel as window content, simplified file browser toggling |
| `Frameworks/DocumentWindow/src/ProjectLayoutView.h/.mm` | Stripped file browser code, now doc+html only |
| `Frameworks/OakTextView/src/OakDocumentView.mm` | Added StatusBarViewModel integration |
| `bin/rave` | Fixed LinkSwift rule (separate from Link) |

## Key Files Reference

| File | Purpose |
|------|---------|
| `Applications/TextMate/src/AppController.mm` | Main app controller, menu wiring |
| `Frameworks/DocumentWindow/src/DocumentWindowController.mm` | Window management, tab/document lifecycle |
| `Frameworks/DocumentWindow/src/DocumentWindowController.h` | Public interface |
| `Frameworks/DocumentWindow/src/ProjectLayoutView.mm` | Split view: editor + HTML output (file browser moved to NavigationSplitView) |
| `Frameworks/OakTextView/src/OakDocumentView.mm` | Editor view + status bar host |
| `Frameworks/OakTextView/src/OakTextView.mm` | Text editing engine (AppKit wrapper around C++) |
| `Frameworks/FileBrowser/src/FileBrowserViewController.mm` | Current file browser (Phase 4 target) |
| `Frameworks/Preferences/src/Preferences.mm` | Current preferences window (Phase 1 target) |
| `Frameworks/OakTabBarView/src/OakTabBarView.mm` | Original tab bar (1369 lines, now bypassed) |

## Remaining Work

### Other Potential Phases
- Replace Preferences window (currently `Preferences.mm` → `SettingsWindowController`)
- Wire TextMateBridge stubs to actual C++ implementations
- Replace remaining AppKit views (HTML output, find panel, etc.)

## Gotchas & Lessons Learned

1. **`NSClassFromString` returns nil if the Swift module isn't linked** — ensure the target chain includes TextMateUI in its `require` list
2. **Closures with block signatures can't be `@objc`** — use `delegate`/`target` + selector dispatch instead
3. **`@ObservationIgnored` is required on callback closures and delegate refs** — otherwise `@Observable` tries to track them
4. **Forward-declare selectors** when sending messages to `id` with complex parameter lists — the ObjC++ compiler errors on unknown selectors
5. **`bin/rave` must be re-run after changing `.rave` files** — it regenerates `build.ninja`; just running `ninja` alone won't pick up dependency changes
6. **The `swift build` in the package dir is for iteration only** — it will show errors for bridge stubs that lack C++ linking. The real build goes through `bin/rave` + `ninja`
7. **Tab bar is in the titlebar** via `NSTitlebarAccessoryViewController` with `layoutAttribute = .bottom`
8. **Single-tab auto-hide**: controlled by `kUserDefaultsDisableTabBarCollapsingKey` preference — when false, tab bar hides with ≤1 document


Developer Documentation
=======================

TextMate is written in Objective-C++: the low-level data structures (mostly non-GUI specific code) are written in C++, the GUI part in Objective-C++ (the C++ part here coming from the need to use the low-level C++ data structures).

## Model

### `oak::basic_tree_t`
This is basically a balanced [binary indexed](http://en.wikipedia.org/wiki/Fenwick_tree) tree. I.e. it has 2 specifics:

* it is *balanced*: this is achieved by using an [AA-tree](http://en.wikipedia.org/wiki/AA_tree)
* it is a *binary indexed tree*: you have O(1) access to `std::accumulate(tree.begin(), it, key_type(), [](key_type const& key, value_type const& value) -> key_type { return key + value.key })` for any `it`

It is a template parameterized by 2 types:

* *`key_type`*: this type has to implement the `+` and `-` operations, and also a default constructor that yields the identity element w.r.t. the operations (i.e. for any `key_type key`, it must hold that `key + key_type() == key_type() + key == key - key_type() == key_type() - key`).
* *`value`*: the value stored by each tree node

When iterating over the values in the tree, the iterator's value type (i.e. what you get from `*it`) has 3 members:

* `offset`: result of `std::accumulate(tree.begin(), it, key_type(), [](key_type const& key, value_type const& value) -> key_type { return key + value.key })`
* `key`: simply a reference to the key user stored in the node
* `value`: simply a reference the value the user stored in the node

Note that for the `key` and `value` members, a reference to the actual object is stored. While it's not a surprise that you can modify the `it->value`, what's really interesting is that you can modify an `it->key` and then call `tree->update_key(it)` to make the tree recalculate the `offset` information for the whole tree (takes O(log(N))).

Unlike the standard associative containers which have a comparison object inherent in their type (as a template parameter), with `oak::basic_tree_t` you pass a comparison object directly to the methods working with comparisons. These are `lower_bound`, `upper_bound` and `find`.

Also unlike the standard comparison object which takes 2 parameters (and models a `<` relation), here the comparison object takes 3 parameters, all of type `key_type`: `search`, `offset` and `key`. The `search` parameter is the one passed to one of the 3 comparison methods above. The `offset` and `key` parameters correspond to an iterator's value_type. The object returns a value in the set {-1, 0, 1}: -1 means iterator's node is "less" than search, 0 means it is "equal" and 1 means it is "more". Analogically to the standard associative containers then, the comparison methods return the following:

* `it = tree.lower_bound(search, comp)`: then `it` is the first node for which `comp(search, it->offset, it->key) != 1` (i.e. the first node that is "not less than" `search`)
* `it = tree.upper_bound(search, comp)`: then `it` is the first node for which `comp(search, it->offset, it->key) == -1` (i.e. the first node that is "more than" `search`)
* `it = tree.find(search, comp)`: `it` is the node for which `comp(search, it->offset, it->key) == 0`, or `tree->end()` if no such node exists (i.e. the first node that is "equal" to `search`)

`oak::basic_tree_t` is a very important data structure in TextMate as it is used in various places and contexts, including text storage, layout, to implement `ng::indexed_map_t` (see later), etc.

### `ng::detail::storage_t`
This is a type used to store a (potentially big) sequence of bytes using chunks of memory stored in `oak::basic_tree_t`. Think of it as an efficient std::string :-). More specifically, inserting and deleting a string in a storage representing a string of length `N` is better than `O(N)`.

### `ng::buffer_t`
This type builds on top of the raw character storage provided by `ng::detail::storage_t` and provides some semantical services for the text stored within it:

* _lines_: it detects newline characters and provides a way to translate between position in text and the line and column number
* _spelling_: it checks the text for spelling errors and provides a way to retrieve them
* _scopes_: it parses the text (using one or more bundles) and assigns one or more *scopes* to some ranges of the text; these usually correspond to various markup or syntax parts of the language the text is written in
* _marks_: TODO

### `ng::indexed_map_t`
This data structure is what it is called:

* it's a *map*: behaves like std::map<ssize_t, ValT> in that it provides the `find`, `lower_bound` and `upper_bound` methods
* it's *indexed*: you get O(log(N)) access to its n-th element for any `n`

It is implemented as an `oak::basic_tree_t` which dictates its `key_type` and provides some services built around the `key_type` members:

* `number_of_children`: this enables the efficient indexing of nodes, i.e. getting the n-th iterator is O(log(N)) (instead of O(N) in the general `oak::basic_tree_t`)
* `length`: this is used for the `std::map`-like functionality.

This structure basically provides a segment tree where a value is valid for a specific `ssize_t` range: `ng::indexed_map_t::iterator it` represents a value `it->value` that is valid in the semi-open range `[it.base()->offset.length, it.base()->offset.length + it.base()->key.length)`, and also that it is the `it->offset.number_of_children`-th value in the indexed map (you can get this more nicely and reliably as `it->index()` which also works if `it == map.end()`).

You can also work with this segment map in the following ways:

* `map.upper_bound(position)`: find a value valid at a given `position`
* `map.set(position, value)`: set a `value` to be valid for a range ending at `position`. The value that was valid at this position before the setting is then valid only after the `position` (the end of the range for the previously valid value remains unchanged). If the `position` was beyond the total range currently represented by the map, then the total range is appropriately extended and the `value` is valid from the end of the previous total range until `position`.
* `map.remove(position)`: remove a value valid exactly until `position`, extending the range of the next value to be valid for the range of the removed value. If this is the last value, then the total range represented by the map gets reduced. Note that if you want to remove a value valid *at* `position` (as opposed to a value valid *exactly until* `position`), you have to do it like `map.remove(map.upper_bound(position)->second)`
* `map.replace(from, to, newLength, bindRight)`: this models replacing a range `(from, to)` with a new one of length `newLength` and making valid for this whole range the value that was previously valid at position `to`.

### `ng::layout_t`
This data structure holds a `ng::buffer_t` and a viewport width and height and provides services for calculating the layout of text, i.e. how the semantical lines (divided by newline character) are divided into visual softlines (induced by wrapping the text at the viewport width and folding), what is the interline spacing, font size etc.. It provides a way to retrieve various geometrical characteristics of ranges of text. Finally, it can use all this information to draw portions of the buffer into a CGContext.

## GUI

### `OakTextView.framework`
The `OakTextView.framework` contains the components you work most with when using TextMate:

* `OakTextView`: the text view itself; it uses a `ng::buffer_t` together with `ng::layout_t` to display text, and among other things, implements input handling consistent with Cocoa's key bindings mechanism.
* `GutterView`: the view left to the text view containing line numbers, folding marks etc.
* `OTVStatusBar`: the bar below the text view containing e.g. current bundle, symbol etc.
* `OakDocumentView`: a view that contains as its subviews an `OakTextView`, `GutterView` and `OTVStatusBar` and makes them work together