import SwiftUI

// MARK: - Find Bar View

/// Inline find/replace bar with Liquid Glass styling.
/// Embedded at the top of the editor area via OakDocumentView's auxiliary view system.
public struct FindBarView: View {
    @Bindable var model: FindBarModel
    @FocusState private var findFieldFocused: Bool

    public init(model: FindBarModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Find row
            findRow

            // Replace row (togglable)
            if model.showReplace {
                replaceRow
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.clear)
        .glassEffect(.regular, in: .rect)
        .onAppear {
            findFieldFocused = true
        }
    }

    // MARK: - Find Row

    private var findRow: some View {
        HStack(spacing: 6) {
            // Toggle replace
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    model.showReplace.toggle()
                }
            } label: {
                Image(systemName: model.showReplace ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Toggle Replace")

            // Find text field
            TextField("Find", text: $model.findString)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($findFieldFocused)
                .onSubmit { model.findNext() }
                .frame(minWidth: 120)

            // Match count
            if !model.findString.isEmpty {
                Text(model.matchDisplay)
                    .font(.system(size: 11))
                    .foregroundStyle(model.matchCount == 0 ? .red : .secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .layoutPriority(1)
            }

            // Prev / Next
            Button { model.findPrevious() } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Previous Match (⇧↩)")
            .disabled(model.findString.isEmpty)

            Button { model.findNext() } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Next Match (↩)")
            .disabled(model.findString.isEmpty)

            Spacer(minLength: 4)

            // Option toggles
            optionToggle("Aa", isOn: $model.ignoreCase, help: "Match Case", invert: true)
            optionToggle(".*", isOn: $model.regularExpression, help: "Regular Expression")
            optionToggle("⤾", isOn: $model.wrapAround, help: "Wrap Around")

            // Close
            Button { model.dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Close (Esc)")
        }
        .frame(height: 24)
    }

    // MARK: - Replace Row

    private var replaceRow: some View {
        HStack(spacing: 6) {
            // Spacer to align with find field (matches chevron width)
            Color.clear.frame(width: 16, height: 1)

            // Replace text field
            TextField("Replace", text: $model.replaceString)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .onSubmit { model.replaceOne() }
                .frame(minWidth: 120)

            // Replace button
            Button("Replace") { model.replaceOne() }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .disabled(model.findString.isEmpty)

            // Replace All button
            Button("All") { model.replaceAll() }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .disabled(model.findString.isEmpty)

            Spacer()
        }
        .frame(height: 24)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Option Toggle

    private func optionToggle(_ label: String, isOn: Binding<Bool>, help: String, invert: Bool = false) -> some View {
        let active = invert ? !isOn.wrappedValue : isOn.wrappedValue
        return Button {
            isOn.wrappedValue.toggle()
        } label: {
            Text(label)
                .font(.system(size: 11, weight: active ? .bold : .regular, design: label == ".*" ? .monospaced : .default))
                .foregroundStyle(active ? .primary : .tertiary)
                .frame(width: 24, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
