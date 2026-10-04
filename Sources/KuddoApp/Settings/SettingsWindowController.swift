import KuddoCore
import AppKit
import SwiftUI

final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    /// Floor for the auto-fit. A pane with two rows in it would otherwise
    /// shrink the window to a sliver — shorter than its own category sidebar.
    /// A floor never reintroduces scrolling; it only leaves slack.
    private static let minContentHeight: CGFloat = 260

    /// Pane content height the window was last sized to. Re-fitting only when
    /// this changes is what keeps us from fighting the user: dragging the
    /// window taller doesn't change a pane's intrinsic height, so we leave it
    /// alone. Switching panes does, so that resizes.
    private var lastFittedPaneHeight: CGFloat = 0

    private static let frameAutosaveName = "Kuddo.SettingsWindow"

    /// True until the first fit when there was no saved frame to restore: the
    /// window doesn't know its height until the pane has laid out, so placing
    /// it waits until then.
    private var placeOnFirstFit = false

    convenience init() {
        let hosting = SettingsHostingController(rootView: SettingsView())
        let window = SettingsWindow(contentViewController: hosting)
        window.title = "Settings"
        window.setContentSize(NSSize(width: 680, height: 560))
        window.styleMask = [.titled, .closable, .resizable]
        // Height floor is deliberately low: the window sizes itself to the
        // selected pane, and General is only a couple of rows tall. (AppKit
        // manages the real limits itself once a window has a contentView-
        // Controller, so the fit below enforces `minContentHeight` directly.)
        window.contentMinSize = NSSize(width: 600, height: Self.minContentHeight)
        window.isReleasedWhenClosed = false        // reuse on next ⌘,
        window.center()                            // near enough until the first fit
        let restored = window.setFrameUsingName(Self.frameAutosaveName)
        self.init(window: window)
        window.windowController = self
        // On the controller, not the window: taking the window over hands it
        // the controller's own autosave name, empty unless set, so a name set
        // on the window beforehand never saved a frame.
        windowFrameAutosaveName = Self.frameAutosaveName
        placeOnFirstFit = !restored
        hosting.onLayout = { [weak self] in self?.fitWindowToPaneIfNeeded() }
        // Catches a font installed while Settings sat open in the background:
        // going off to install one makes another app key, and coming back
        // makes this window key again. `show()` covers the first open and the
        // case where the window is already key, which posts nothing.
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main
        ) { _ in FontCatalogStore.shared.refresh() }
    }

    /// Closes the Settings window if it's on screen, leaving it alone if it was
    /// never opened.
    ///
    /// Deliberately goes through `NSApp.windows` rather than `shared`, which is
    /// lazy: touching it here would build the whole SwiftUI hierarchy just to
    /// discover there was nothing to close, on every window close.
    static func closeIfOpen() {
        for window in NSApp.windows where window.windowController is SettingsWindowController {
            window.close()
        }
    }

    /// `focus` opens the pane a control lives in and puts the focus ring on
    /// the control itself — the same landing a Settings search result gets.
    /// It's how a ⌘K row like "Appearance › Stroke weight" finishes the job:
    /// arriving in the right pane and still having to hunt for the row would
    /// be most of the work left undone.
    static func show(focus field: SettingsField? = nil) {
        FontCatalogStore.shared.refresh()
        shared.showWindow(nil)
        shared.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if let field { SettingsRoute.shared.requested = field }
    }

    /// Sizes the window so the selected pane fits without scrolling, the way
    /// System Settings does. Only the height moves — the user's width stays —
    /// and growth stops at the edge of the screen, so a pane taller than the
    /// display still scrolls rather than running off it.
    private func fitWindowToPaneIfNeeded() {
        guard let window,
              let contentView = window.contentView,
              let scroll = Self.paneScrollView(in: contentView),
              let document = scroll.documentView
        else { return }

        let paneHeight = document.frame.height
        guard paneHeight > 1, abs(paneHeight - lastFittedPaneHeight) > 1 else { return }
        let isFirstFit = lastFittedPaneHeight == 0
        lastFittedPaneHeight = paneHeight

        // Anything laid out outside the scroller (inset headers and the like)
        // still needs room, so measure it rather than assuming zero.
        let chrome = max(0, contentView.frame.height - scroll.contentView.bounds.height)
        var targetContentHeight = max(paneHeight + chrome, Self.minContentHeight)

        var targetFrame = window.frameRect(forContentRect: NSRect(
            x: 0, y: 0, width: contentView.frame.width, height: targetContentHeight))
        let visible = (window.screen ?? NSScreen.main)?.visibleFrame
        if let visible {
            let titleBar = targetFrame.height - targetContentHeight
            targetContentHeight = min(targetContentHeight, visible.height - titleBar)
            targetFrame = window.frameRect(forContentRect: NSRect(
                x: 0, y: 0, width: contentView.frame.width, height: targetContentHeight))
        }

        var frame = window.frame
        if placeOnFirstFit, let visible {
            // Nowhere saved to go back to, so it goes where `center()` would
            // put a window of its final size.
            placeOnFirstFit = false
            frame.size.height = targetFrame.height
            frame.origin = Self.restingOrigin(for: frame.size, in: visible)
        } else {
            guard abs(frame.height - targetFrame.height) > 1 else { return }
            // Grow downward: the title bar stays put instead of the window
            // creeping up the screen every time you switch panes...
            frame.origin.y += frame.height - targetFrame.height
            frame.size.height = targetFrame.height
            // ...unless the bottom would run past the screen's, in which case
            // it moves to where opening puts it rather than as little as
            // possible, which left it sitting flat on the Dock.
            if let visible, frame.minY < visible.minY {
                frame.origin.y = Self.restingOrigin(for: frame.size, in: visible).y
            }
        }
        frame = window.constrainFrameRect(frame, to: window.screen)

        // Out of the layout pass that triggered us — resizing re-enters layout.
        DispatchQueue.main.async {
            window.setFrame(frame, display: true,
                            animate: !isFirstFit && window.isVisible)
        }
    }

    /// Centred across, with the spare height split a third above and two
    /// thirds below: slightly above centre, as `NSWindow.center()` places a
    /// window.
    private static func restingOrigin(for size: NSSize, in visible: NSRect) -> NSPoint {
        NSPoint(x: visible.midX - size.width / 2,
                y: visible.minY + max(0, visible.height - size.height) * 2 / 3)
    }

    /// The detail pane's scroll view — the widest one in the window, since the
    /// category sidebar's list is always narrower. Returns nil if SwiftUI ever
    /// stops backing a grouped `Form` with a scroll view, in which case the
    /// window simply keeps whatever size it has.
    private static func paneScrollView(in root: NSView) -> NSScrollView? {
        var found: [NSScrollView] = []
        func walk(_ view: NSView) {
            if let scroll = view as? NSScrollView { found.append(scroll) }
            view.subviews.forEach(walk)
        }
        walk(root)
        return found.filter { $0.frame.width > 300 }
                    .max { $0.frame.width < $1.frame.width }
    }
}

/// Hosting controller that reports every AppKit layout pass, which is how the
/// window learns that the selected pane (and so the content height) changed.
/// A control something outside Settings asked it to open on.
///
/// A one-value channel rather than a parameter on `SettingsView`, because the
/// window is built once and reused: the second ⌘K row that opens Settings has
/// no new view to hand a parameter to, only a live one to steer.
final class SettingsRoute: ObservableObject {
    static let shared = SettingsRoute()
    @Published var requested: SettingsField?
    private init() {}
}

private final class SettingsHostingController: NSHostingController<SettingsView> {
    var onLayout: (() -> Void)?

    override func viewDidLayout() {
        super.viewDidLayout()
        onLayout?()
    }
}

/// NSWindow subclass that closes on Esc (and ⌘.) via the responder chain's
/// `cancelOperation(_:)` hook.
private final class SettingsWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) {
        performClose(sender)
    }
}
