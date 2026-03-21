import SwiftUI

@objc private protocol PerformCloseTarget {
    func performClose(_ sender: Any?)
}

// MARK: - Editor Container View

/// Thin NSView wrapper around OakDocumentView. Replaces ProjectLayoutView.
/// Routes `performClose:` to the window delegate (DocumentWindowController)
/// so Cmd-W correctly closes a tab or the window.
final class EditorContainerView: NSView {
    private weak var embeddedView: NSView?

    override var mouseDownCanMoveWindow: Bool { false }

    @objc func performClose(_ sender: Any?) {
        if let target = window?.delegate as? PerformCloseTarget {
            target.performClose(sender)
        } else {
            NSSound.beep()
        }
    }

    func embed(_ view: NSView?) {
        guard view !== embeddedView else { return }

        embeddedView?.removeFromSuperview()
        embeddedView = nil

        guard let view else { return }

        view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: topAnchor),
            view.bottomAnchor.constraint(equalTo: bottomAnchor),
            view.leadingAnchor.constraint(equalTo: leadingAnchor),
            view.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        embeddedView = view
    }
}

// MARK: - Editor View Representable

/// Specialized NSViewRepresentable for embedding the OakDocumentView in SwiftUI.
struct EditorViewRepresentable: NSViewRepresentable {
    var editorView: NSView?

    func makeNSView(context: Context) -> EditorContainerView {
        let container = EditorContainerView()
        container.embed(editorView)
        return container
    }

    func updateNSView(_ container: EditorContainerView, context: Context) {
        container.embed(editorView)
    }
}
