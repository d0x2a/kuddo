import AppKit

/// The icon, caption, details and button of a `HeldSizeSurround`, over the
/// surround the renderer draws around a held grid. Apart from its button it
/// is a label: a click anywhere else goes through to the terminal under it.
final class HeldSizeBadgeView: NSView {
    static let iconSide: CGFloat = 32
    /// Kept clear between the badge and the edges of the strip it sits in.
    static let padding: CGFloat = 16
    /// Narrower than this, a truncated line says nothing, so it is dropped.
    static let minTextWidth: CGFloat = 64

    /// One row of the badge, top to bottom.
    private enum Part: CaseIterable {
        case icon, caption, details, button

        /// Space above this part when something is above it.
        var gap: CGFloat {
            switch self {
            case .icon: return 0
            case .caption: return 6
            case .details: return 2
            case .button: return 10
            }
        }
    }

    private let imageView = NSImageView()
    private let captionLabel = NSTextField(labelWithString: "")
    /// One single-line label per detail, so each truncates on its own.
    private var detailLabels: [NSTextField] = []
    private let button = NSButton(title: "", target: nil, action: nil)
    private var perform: (() -> Void)?
    /// The parts it was given, in order.
    private var parts: [Part] = []
    /// What the last `place` was given, so a frame that leaves the strips as
    /// they were doesn't measure the text again.
    private var placedIn: [CGRect]?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point), hit === button || hit.isDescendant(of: button)
        else { return nil }
        return hit
    }

    init() {
        super.init(frame: .zero)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        captionLabel.font = .systemFont(ofSize: 11, weight: .medium)
        captionLabel.alignment = .center
        captionLabel.lineBreakMode = .byTruncatingTail
        captionLabel.maximumNumberOfLines = 1
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        // A click shouldn't take the keyboard away from the terminal.
        button.refusesFirstResponder = true
        button.target = self
        button.action = #selector(buttonPressed)
        for view in [imageView, captionLabel, button] as [NSView] { addSubview(view) }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// `color` is the text's and a template icon's; `dark` picks the button's
    /// appearance to suit the terminal's background rather than the system's.
    func configure(_ surround: HeldSizeSurround, color: NSColor, dark: Bool) {
        appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let symbol = NSImage.SymbolConfiguration(pointSize: 26, weight: .regular)
        imageView.image = surround.icon.map { $0.withSymbolConfiguration(symbol) ?? $0 }
        imageView.contentTintColor = color
        captionLabel.stringValue = surround.caption ?? ""
        captionLabel.textColor = color
        let details = surround.details.filter { !$0.isEmpty }
        detailLabels.forEach { $0.removeFromSuperview() }
        detailLabels = details.map { line in
            let label = NSTextField(labelWithString: line)
            label.font = .systemFont(ofSize: 10)
            label.alignment = .center
            label.lineBreakMode = .byTruncatingTail
            label.maximumNumberOfLines = 1
            label.textColor = color.withAlphaComponent(color.alphaComponent * 0.75)
            addSubview(label)
            return label
        }
        button.title = surround.action?.title ?? ""
        button.isEnabled = true
        perform = surround.action?.perform

        parts = Part.allCases.filter {
            switch $0 {
            case .icon: return surround.icon != nil
            case .caption: return !(surround.caption ?? "").isEmpty
            case .details: return !details.isEmpty
            case .button: return surround.action != nil
            }
        }
        placedIn = nil
    }

    @objc private func buttonPressed() {
        // Once: the holder lets go in its own time, and a second click
        // before then would ask it twice.
        button.isEnabled = false
        perform?()
    }

    /// Centres the badge in whichever of `strips` — rects in the superview's
    /// coordinates, most wanted first — shows the most of it, the earlier one
    /// on a tie. Short of room, the details go first, then the icon, then the
    /// caption; the button stays to the last, since it is the one part that
    /// does something. With room for none of it the badge hides.
    func place(in strips: [CGRect]) {
        guard strips != placedIn else { return }
        placedIn = strips

        let sizes: [Part: CGSize] = [
            .icon: CGSize(width: Self.iconSide, height: Self.iconSide),
            .caption: captionLabel.fittingSize,
            .details: detailsSize(),
            .button: button.fittingSize,
        ]
        var options: [[Part]] = []
        var shown = parts
        for dropped in [Part.details, .icon, .caption] {
            if !options.contains(shown), !shown.isEmpty { options.append(shown) }
            shown.removeAll { $0 == dropped }
        }
        if !options.contains(shown), !shown.isEmpty { options.append(shown) }

        var best: (frame: CGRect, parts: [Part])?
        for strip in strips {
            let room = strip.insetBy(dx: Self.padding, dy: Self.padding)
            guard room.width > 0, room.height > 0 else { continue }
            for option in options {
                if let best, best.parts.count >= option.count { break }
                guard let size = Self.size(of: option, sizes: sizes, within: room.size) else { continue }
                let frame = CGRect(x: (room.midX - size.width / 2).rounded(),
                                   y: (room.midY - size.height / 2).rounded(),
                                   width: ceil(size.width), height: ceil(size.height))
                best = (frame, option)
                break
            }
        }

        guard let best else {
            isHidden = true
            return
        }
        isHidden = false
        frame = best.frame
        var y: CGFloat = 0
        for part in Part.allCases {
            let views = self.views(for: part)
            guard best.parts.contains(part), let size = sizes[part] else {
                views.forEach { $0.isHidden = true }
                continue
            }
            if part != best.parts.first { y += part.gap }
            let width = part == .icon || part == .button ? size.width : best.frame.width
            for view in views {
                let height = part == .details ? ceil(view.fittingSize.height) : ceil(size.height)
                view.isHidden = false
                view.frame = CGRect(x: ((best.frame.width - width) / 2).rounded(), y: y,
                                    width: ceil(width), height: height)
                y += height
            }
        }
    }

    /// The badge's size showing `parts`, or nil if it doesn't fit `room`. Text
    /// wider than the room truncates, down to `minTextWidth`.
    private static func size(of parts: [Part], sizes: [Part: CGSize], within room: CGSize) -> CGSize? {
        var width: CGFloat = 0
        var height: CGFloat = 0
        for part in parts {
            guard let size = sizes[part] else { continue }
            switch part {
            case .caption, .details:
                if room.width < min(size.width, minTextWidth) { return nil }
                width = max(width, min(size.width, room.width))
            case .icon, .button:
                width = max(width, size.width)
            }
            if part != parts.first { height += part.gap }
            height += ceil(size.height)
        }
        guard width <= room.width, height <= room.height else { return nil }
        return CGSize(width: width, height: height)
    }

    /// The detail lines stacked, as wide as the widest.
    private func detailsSize() -> CGSize {
        let sizes = detailLabels.map(\.fittingSize)
        return CGSize(width: sizes.map(\.width).max() ?? 0,
                      height: sizes.reduce(0) { $0 + ceil($1.height) })
    }

    private func views(for part: Part) -> [NSView] {
        switch part {
        case .icon: return [imageView]
        case .caption: return [captionLabel]
        case .details: return detailLabels
        case .button: return [button]
        }
    }
}
