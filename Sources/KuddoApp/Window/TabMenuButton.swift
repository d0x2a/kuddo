import AppKit

/// The tabs button at the right of the title bar. A click opens a menu of the
/// window's tabs, which is the way to them at a glance when they aren't on
/// screen (`TabPlacement.hidden`). An orange dot on it says a tab wants you,
/// the sidebar's waiting marker for a window that may not be showing one.
final class TabMenuButton: NSView {
    /// Builds the menu at the moment of the click, so it lists the tabs as
    /// they are now.
    var makeMenu: (() -> NSMenu)?

    var showsAttention = false {
        didSet { if showsAttention != oldValue { dot.isHidden = !showsAttention } }
    }

    private let button = NSButton()
    private let dot = NSView()
    private static let dotSize: CGFloat = 6

    /// The title bar's height and a little room either side; the title bar
    /// lays an accessory out by its frame.
    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 34, height: 28))

        button.image = NSImage(systemSymbolName: "square.on.square",
                               accessibilityDescription: "Tabs")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .regular))
        button.imagePosition = .imageOnly
        button.isBordered = false
        button.contentTintColor = .secondaryLabelColor
        button.toolTip = "Tabs"
        button.target = self
        button.action = #selector(showMenu(_:))
        button.translatesAutoresizingMaskIntoConstraints = false
        addSubview(button)

        dot.wantsLayer = true
        dot.layer?.cornerRadius = Self.dotSize / 2
        dot.isHidden = true
        dot.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dot)

        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: centerXAnchor),
            button.centerYAnchor.constraint(equalTo: centerYAnchor),
            button.widthAnchor.constraint(equalToConstant: 24),
            button.heightAnchor.constraint(equalToConstant: 22),
            // On the symbol's upper right corner, like a badge.
            dot.widthAnchor.constraint(equalToConstant: Self.dotSize),
            dot.heightAnchor.constraint(equalToConstant: Self.dotSize),
            dot.centerXAnchor.constraint(equalTo: button.centerXAnchor, constant: 7),
            dot.centerYAnchor.constraint(equalTo: button.centerYAnchor, constant: -6),
        ])
        colorDot()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        colorDot()
    }

    private func colorDot() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            dot.layer?.backgroundColor = NSColor.systemOrange.cgColor
        }
    }

    /// Under the button, its right edge on the button's: the button sits at
    /// the window's right edge, and a menu opening rightward from it would
    /// be pushed back by the screen edge anyway.
    @objc private func showMenu(_ sender: Any?) {
        guard let menu = makeMenu?() else { return }
        let origin = NSPoint(x: bounds.maxX - menu.size.width,
                             y: isFlipped ? bounds.maxY + 2 : bounds.minY - 2)
        button.highlight(true)
        menu.popUp(positioning: nil, at: origin, in: self)
        button.highlight(false)
    }
}
