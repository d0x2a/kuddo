import AppKit
import SwiftUI

/// Tab stops that are AppKit views holding first responder themselves,
/// rather than SwiftUI controls focused through `SettingsView`'s focus state.
///
/// SwiftUI would not move focus from a text field onto a button beside it:
/// Tab out of an environment row's Value field asked for its Cancel button
/// and focus landed nowhere, so the next Tab started over at Name. A button
/// that takes first responder itself doesn't depend on that.
///
/// Tab pressed on one still reaches `SettingsView`'s handler, but with the
/// focus state nil, so the handler asks `focused` where it is.
@MainActor
final class SettingsKeyViews {
    static let shared = SettingsKeyViews()

    private struct Entry { weak var view: NSView? }
    private var entries: [SettingsField: Entry] = [:]

    func register(_ view: NSView, as field: SettingsField) {
        entries[field] = Entry(view: view)
    }

    func unregister(_ view: NSView) {
        entries = entries.filter { $0.value.view != nil && $0.value.view !== view }
    }

    /// The view standing for `field`, while it's in a window.
    func view(for field: SettingsField) -> NSView? {
        guard let view = entries[field]?.view, view.window != nil else { return nil }
        return view
    }

    /// The stop whose view holds first responder, if one does. The focus
    /// state reads nil then.
    var focused: SettingsField? {
        entries.first { _, entry in
            guard let view = entry.view else { return false }
            return view.window?.firstResponder === view
        }?.key
    }
}

/// A push button that takes keyboard focus however Full Keyboard Access is
/// set. AppKit buttons only accept first responder with it on, and it's a
/// system-wide setting most people leave off.
final class SettingsKeyButton: NSButton {
    override var acceptsFirstResponder: Bool { isEnabled }
    override var canBecomeKeyView: Bool { isEnabled && !isHiddenOrHasHiddenAncestor }

    /// Space and Return press it, as they do the SwiftUI controls around it.
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 49, 76:   // Return, Space, keypad Enter
            if isEnabled { performClick(nil) }
        default:
            super.keyDown(with: event)
        }
    }
}

/// `SettingsKeyButton` in SwiftUI, standing for `field` in the Tab order.
struct SettingsButton: NSViewRepresentable {
    let title: String
    let field: SettingsField
    /// Filled with the accent colour, the way `.borderedProminent` draws.
    var prominent = false
    var enabled = true
    let action: () -> Void

    func makeNSView(context: Context) -> SettingsKeyButton {
        let button = SettingsKeyButton(title: title, target: context.coordinator,
                                       action: #selector(Coordinator.press))
        button.bezelStyle = .push
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        return button
    }

    func updateNSView(_ button: SettingsKeyButton, context: Context) {
        context.coordinator.action = action
        button.title = title
        button.isEnabled = enabled
        // Grey while it can't be pressed, as a disabled prominent button is.
        button.bezelColor = prominent && enabled ? .controlAccentColor : nil
        SettingsKeyViews.shared.register(button, as: field)
    }

    static func dismantleNSView(_ button: SettingsKeyButton, coordinator: Coordinator) {
        SettingsKeyViews.shared.unregister(button)
    }

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func press() { action() }
    }
}
