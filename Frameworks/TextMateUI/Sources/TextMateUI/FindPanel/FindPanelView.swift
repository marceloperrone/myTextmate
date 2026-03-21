import SwiftUI

// MARK: - Find Panel View

/// Floating Find panel with Liquid Glass styling for project/folder/open-files search.
/// Replaces the programmatic AppKit UI in Find.mm while preserving the results outline
/// and status bar as NSViewRepresentable pass-throughs.
public struct FindPanelView: View {
    @Bindable var model: FindPanelModel
    @FocusState private var findFieldFocused: Bool
    @FocusState private var replaceFieldFocused: Bool

    public init(model: FindPanelModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Search form with glass effect
            formSection
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 8)

            // Results outline (existing AppKit via NSViewRepresentable)
            if model.showResults, model.resultsView != nil {
                AppKitPassthroughView(view: model.resultsView)
                    .frame(minHeight: 50, maxHeight: .infinity)
            }

            // Status bar (existing AppKit via NSViewRepresentable)
            if model.statusBarView != nil {
                AppKitPassthroughView(view: model.statusBarView)
                    .frame(height: 24)
            }

            // Action buttons
            buttonsSection
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
        }
        .onAppear {
            findFieldFocused = true
        }
    }

    // MARK: - Form Section

    private var formSection: some View {
        VStack(spacing: 8) {
            // Find row
            findRow

            // Replace row
            replaceRow

            // Options row
            optionsRow

            // Where row
            whereRow
        }
    }

    // MARK: - Find Row

    private var findRow: some View {
        HStack(spacing: 6) {
            Text("Find:")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .trailing)

            TextField("", text: $model.findString)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
                .focused($findFieldFocused)
                .onSubmit { model.findNext() }

            Button {
                model.showFindHistory()
            } label: {
                Image(systemName: "chevron.down.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Show Find History")

            Button {
                model.countOccurrences()
            } label: {
                Text("\u{03A3}")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Show Results Count")
            .disabled(model.findString.isEmpty)
        }
    }

    // MARK: - Replace Row

    private var replaceRow: some View {
        HStack(spacing: 6) {
            Text("Replace:")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .trailing)

            TextField("", text: $model.replaceString)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
                .focused($replaceFieldFocused)
                .onSubmit { model.replaceAndFind() }

            Button {
                model.showReplaceHistory()
            } label: {
                Image(systemName: "chevron.down.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Show Replace History")
        }
    }

    // MARK: - Options Row

    private var optionsRow: some View {
        HStack(spacing: 6) {
            Text("Options:")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .trailing)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 16) {
                    Toggle("Regular Expression", isOn: $model.regularExpression)
                    Toggle("Ignore Whitespace", isOn: $model.ignoreWhitespace)
                        .disabled(!model.canIgnoreWhitespace)
                }
                HStack(spacing: 16) {
                    Toggle("Ignore Case", isOn: $model.ignoreCase)
                    Toggle("Wrap Around", isOn: $model.wrapAround)
                }
            }
            .toggleStyle(.checkbox)
            .font(.system(size: 12))

            Spacer()
        }
    }

    // MARK: - Where Row

    private var whereRow: some View {
        HStack(spacing: 6) {
            Text("In:")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .trailing)

            // Where popup (wrapped NSPopUpButton from Find.mm)
            if let popUp = model.wherePopUpButton {
                AppKitPassthroughView(view: popUp)
                    .frame(maxWidth: 150, maxHeight: 24)
            }

            Text("matching")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            TextField("", text: $model.globString)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
                .disabled(!model.canEditGlob)
                .frame(maxWidth: 200)
                .onSubmit {
                    _ = model.target?.perform(NSSelectorFromString("findPanelDidChangeGlob:"), with: model)
                }

            // Actions popup (wrapped NSPopUpButton from Find.mm)
            if let actionsButton = model.actionsPopUpButton {
                AppKitPassthroughView(view: actionsButton)
                    .frame(maxHeight: 24)
            }
        }
    }

    // MARK: - Buttons Section

    private var buttonsSection: some View {
        HStack(spacing: 8) {
            Button("Find All") { model.findAll() }
                .disabled(model.findString.isEmpty)

            Button(model.replaceAllButtonTitle) { model.replaceAll() }
                .disabled(model.findString.isEmpty || !model.canReplaceAll)

            Spacer()

            Button("Replace") { model.replaceOne() }
                .disabled(model.findString.isEmpty || !model.canReplaceInDocument)

            Button("Replace & Find") { model.replaceAndFind() }
                .disabled(model.findString.isEmpty || !model.canReplaceInDocument)

            Button("Previous") { model.findPrevious() }
                .disabled(model.findString.isEmpty)

            Button("Next") { model.findNext() }
                .keyboardShortcut(.defaultAction)
                .disabled(model.findString.isEmpty)
        }
    }
}

// MARK: - AppKit Passthrough View

/// NSViewRepresentable that displays an existing AppKit NSView within SwiftUI.
/// Used to embed FFResultsViewController, FFStatusBarViewController, and NSPopUpButtons.
struct AppKitPassthroughView: NSViewRepresentable {
    var view: NSView?

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        if let view {
            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(view)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                view.topAnchor.constraint(equalTo: container.topAnchor),
                view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])
        }
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        // If the view changed, re-embed it
        guard let view else { return }
        if view.superview !== container {
            container.subviews.forEach { $0.removeFromSuperview() }
            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(view)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                view.topAnchor.constraint(equalTo: container.topAnchor),
                view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])
        }
    }
}
