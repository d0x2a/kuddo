import AppKit
import KuddoRender

/// What a tab shows around its grid while something holds it at a size other
/// than its window's (`Session.holdSize`). The grid sits in the window's
/// top-left; this fills the rest, so the end of the grid reads as an edge
/// rather than as blank cells, and says who is holding it.
///
/// Colours come from the tab's theme — its foreground, faint — so the
/// surround suits whatever palette the tab is in.
package struct HeldSizeSurround {
    /// A button under the rest of the badge.
    package struct Action {
        package var title: String
        /// Called on the main thread when the button is clicked, once: the
        /// button stays disabled until the surround is set again. Showing it
        /// is all Kuddo does; letting go of the tab is up to the holder,
        /// with `releaseSize` as ever.
        package var perform: () -> Void

        package init(title: String, perform: @escaping () -> Void) {
            self.title = title
            self.perform = perform
        }
    }

    package enum Pattern {
        /// A faint wash and the edge of the grid, no pattern.
        case plain
        /// Fine 45° lines.
        case stripes
        /// A staggered grid of dots.
        case dots
    }

    package var pattern: Pattern
    /// Shown in the larger of the two strips the grid leaves, above the
    /// caption. A template image, as SF Symbols are, takes the theme's
    /// colour; a symbol is drawn at a fixed point size, any other image
    /// scaled to fit the same square.
    package var icon: NSImage?
    /// One line under the icon, truncated to fit: the client's name, say.
    package var caption: String?
    /// Smaller, fainter lines under the caption, one each, truncated to fit:
    /// the size it is held at, how it is connected. The first part of the
    /// badge to go when there isn't room for all of it.
    package var details: [String]
    /// A button at the bottom of the badge — "Disconnect", say. The last
    /// part of the badge to go when there isn't room.
    package var action: Action?

    package init(pattern: Pattern = .stripes, icon: NSImage? = nil, caption: String? = nil,
                 details: [String] = [], action: Action? = nil) {
        self.pattern = pattern
        self.icon = icon
        self.caption = caption
        self.details = details
        self.action = action
    }

    /// Whether there is anything for the badge to show.
    var hasBadge: Bool {
        icon != nil || !(caption ?? "").isEmpty || details.contains { !$0.isEmpty } || action != nil
    }
}

extension HeldSizeSurround.Pattern {
    var rendered: SurroundPattern {
        switch self {
        case .plain: return .plain
        case .stripes: return .stripes
        case .dots: return .dots
        }
    }
}
