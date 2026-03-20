import SwiftUI

// MARK: - Status Bar View

public struct StatusBarView: View {
	@Bindable var model: StatusBarViewModel

	public init(model: StatusBarViewModel) {
		self.model = model
	}

	public var body: some View {
		VStack(spacing: 0) {
			HStack(spacing: 0) {
				selectionDisplay
					.frame(minWidth: 50, maxWidth: 225)

				statusDivider

				grammarMenu
					.frame(minWidth: 50, maxWidth: 225)

				statusDivider

				tabSizeMenu

				statusDivider

				BundleItemsPopUpView(model: model)
					.frame(width: 31)

				statusDivider

				SymbolPopUpView(
					model: model,
					title: model.symbolName.isEmpty ? "Symbols" : model.symbolName
				)
				.frame(minWidth: 50, maxWidth: .infinity)

			}
			.padding(.horizontal, 10)
			.frame(height: 24)
		}
		.background(.clear)
		.glassEffect(.regular, in: .rect)
	}

	// MARK: - Selection Display

	private var selectionDisplay: some View {
		HStack(spacing: 4) {
			Text("Line:")
				.statusBarFont()
				.foregroundStyle(.secondary)

			Text(model.formattedSelection)
				.statusBarFont()
				.monospacedDigit()
				.foregroundStyle(.secondary)
				.lineLimit(1)
				.truncationMode(.tail)
		}
	}

	// MARK: - Grammar Menu

	private var grammarMenu: some View {
		Menu {
			ForEach(model.currentGrammarEntries, id: \.uuid) { entry in
				Button(entry.name) {
					model.selectGrammar(uuid: entry.uuid)
				}
			}
			if model.currentGrammarEntries.isEmpty {
				Text("No Grammars Loaded")
			}
		} label: {
			Text(model.grammarName.isEmpty ? "(no grammar)" : model.grammarName)
				.statusBarFont()
				.foregroundStyle(.secondary)
				.lineLimit(1)
				.truncationMode(.middle)
		}
		.menuStyle(.borderlessButton)
		.accessibilityLabel("Grammar")
	}

	// MARK: - Tab Size Menu

	private var tabSizeMenu: some View {
		Menu {
			Section("Indent Size") {
				ForEach([2, 3, 4, 8], id: \.self) { size in
					Button("\(size)") {
						model.selectTabSize(size)
					}
				}
				Button("Other\u{2026}") {
					model.showTabSizePanel()
				}
			}

			Divider()

			Section("Indent Using") {
				Button("Tabs") {
					model.setIndentWithTabs()
				}
				Button("Spaces") {
					model.setIndentWithSpaces()
				}
			}
		} label: {
			Text(model.tabSizeDisplay)
				.statusBarFont()
				.foregroundStyle(.secondary)
				.lineLimit(1)
		}
		.menuStyle(.borderlessButton)
	}

	// MARK: - Divider

	private var statusDivider: some View {
		Rectangle()
			.fill(.separator)
			.frame(width: 1, height: 15)
			.padding(.horizontal, 4)
	}
}

// MARK: - Bundle Items PopUp (NSViewRepresentable)

struct BundleItemsPopUpView: NSViewRepresentable {
	let model: StatusBarViewModel

	func makeNSView(context: Context) -> NSPopUpButton {
		let popup = NSPopUpButton(frame: .zero, pullsDown: true)
		popup.font = NSFont.systemFont(ofSize: 11)
		popup.isBordered = false
		popup.setAccessibilityLabel("Bundle Item")

		let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
		item.image = NSImage(named: NSImage.actionTemplateName)
		(popup.cell as? NSPopUpButtonCell)?.usesItemFromMenu = false
		(popup.cell as? NSPopUpButtonCell)?.menuItem = item

		model.bundleItemsPopUp = popup

		NotificationCenter.default.addObserver(
			context.coordinator,
			selector: #selector(Coordinator.willPopUp(_:)),
			name: NSPopUpButton.willPopUpNotification,
			object: popup
		)

		return popup
	}

	func updateNSView(_ nsView: NSPopUpButton, context: Context) {}

	func makeCoordinator() -> Coordinator {
		Coordinator(model: model)
	}

	@MainActor class Coordinator: NSObject {
		let model: StatusBarViewModel
		init(model: StatusBarViewModel) { self.model = model }

		@objc func willPopUp(_ notification: Notification) {
			guard let popup = notification.object as? NSPopUpButton else { return }
			let sel = NSSelectorFromString("showBundleItemSelector:")
			if let d = model.delegate, d.responds(to: sel) {
				_ = d.perform(sel, with: popup)
			}
		}
	}
}

// MARK: - Symbol PopUp (NSViewRepresentable)

struct SymbolPopUpView: NSViewRepresentable {
	let model: StatusBarViewModel
	let title: String

	func makeNSView(context: Context) -> NSPopUpButton {
		let popup = NSPopUpButton(frame: .zero, pullsDown: false)
		popup.font = NSFont.systemFont(ofSize: 11)
		popup.isBordered = false
		popup.setAccessibilityLabel("Symbol")
		popup.addItem(withTitle: title)

		NotificationCenter.default.addObserver(
			context.coordinator,
			selector: #selector(Coordinator.willPopUp(_:)),
			name: NSPopUpButton.willPopUpNotification,
			object: popup
		)

		return popup
	}

	func updateNSView(_ nsView: NSPopUpButton, context: Context) {
		if nsView.titleOfSelectedItem != title {
			nsView.menu?.removeAllItems()
			nsView.addItem(withTitle: title)
		}
	}

	func makeCoordinator() -> Coordinator {
		Coordinator(model: model)
	}

	@MainActor class Coordinator: NSObject {
		let model: StatusBarViewModel
		init(model: StatusBarViewModel) { self.model = model }

		@objc func willPopUp(_ notification: Notification) {
			guard let popup = notification.object as? NSPopUpButton else { return }
			let sel = NSSelectorFromString("showSymbolSelector:")
			if let d = model.delegate, d.responds(to: sel) {
				_ = d.perform(sel, with: popup)
			}
		}
	}
}

// MARK: - Status Bar Font Modifier

private extension View {
	func statusBarFont() -> some View {
		self.font(.system(size: 11))
	}
}
