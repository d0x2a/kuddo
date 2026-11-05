import KuddoCore
import AppKit

/// The tabs along the top of the window, under the title bar
/// (`TabPlacement.top`). One line a tab: the status marker, the title and the
/// ⌘-number. The process and directory the sidebar shows under a title are
/// the tab's tooltip here. Tabs share the width between `minTabWidth` and
/// `maxTabWidth`, and scroll sideways once they no longer fit.
final class TabStripView: NSView {
    static let height: CGFloat = 32
    /// Below this a title is mostly ellipsis, so the strip scrolls instead.
    private static let minTabWidth: CGFloat = 110
    /// Wide enough for a long title; past it a lone tab would stretch across
    /// the window and read as a second title bar.
    private static let maxTabWidth: CGFloat = 240
    private static let inset: CGFloat = 4

    weak var delegate: TabListDelegate?

    private let scrollView = NSScrollView()
    private let document = TabDropView()
    private var chips: [TabChipView] = []
    /// Hairlines between tabs, so where one ends is plain without a
    /// highlight. None beside the active tab: its highlight says it already.
    private var dividers: [NSView] = []
    private var activeId: UUID?
    private let dropIndicator = NSView()
    private let separator = NSView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.verticalScrollElasticity = .none
        scrollView.drawsBackground = false
        scrollView.documentView = document
        addSubview(scrollView)

        separator.wantsLayer = true
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: separator.topAnchor),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1),
        ])

        dropIndicator.wantsLayer = true
        dropIndicator.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        dropIndicator.layer?.cornerRadius = 1
        dropIndicator.isHidden = true
        document.addSubview(dropIndicator)

        document.registerForDraggedTypes([.kuddoTab])
        document.onDragChanged = { [weak self] point in
            self?.handleDragChanged(at: point) ?? false
        }
        document.onDragPerform = { [weak self] point, info in
            self?.handleDrop(at: point, info: info) ?? false
        }

        applyTheme()
        NotificationCenter.default.addObserver(
            self, selector: #selector(themeDidChange),
            name: .kuddoThemeDidChange, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func themeDidChange() { applyTheme() }

    /// The arrow, stated rather than inherited: whatever cursor the pointer
    /// brings in otherwise stays until something sets another. (Not on the
    /// sidebar, where it would cover the divider's grab zone; the strip is
    /// never shown with the sidebar, so it has no divider beside it.)
    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .arrow)
    }

    /// The sidebar's tint, so the tabs look the same wherever they are.
    private func applyTheme() {
        layer?.backgroundColor = TabListStyle.panelColor().cgColor
        separator.layer?.backgroundColor = TabListStyle.separatorColor().cgColor
        colorDividers()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        colorDividers()
    }

    /// The system separator, resolved for this view's appearance: a layer
    /// colour doesn't follow light and dark by itself.
    private func colorDividers() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let color = NSColor.separatorColor.cgColor
            for divider in dividers { divider.layer?.backgroundColor = color }
        }
    }

    func update(tabs: [TabEntry], activeId: UUID?) {
        // Rebuilt only when the tabs themselves change, for the reason
        // `SidebarView.update` gives: a view torn down under the pointer
        // cancels the press AppKit is tracking.
        let rebuilt = chips.map(\.id) != tabs.map(\.id)
        if rebuilt { rebuildChips(for: tabs) }
        for (idx, tab) in tabs.enumerated() {
            chips[idx].apply(tab,
                             isActive: tab.id == activeId,
                             badge: TabListStyle.badge(at: idx, of: tabs.count))
        }
        let activeIdx = tabs.firstIndex { $0.id == activeId }
        for (i, divider) in dividers.enumerated() {
            divider.isHidden = activeIdx == i || activeIdx == i + 1
        }
        if rebuilt || activeId != self.activeId {
            self.activeId = activeId
            layoutTabs()
            if let chip = chips.first(where: { $0.id == activeId }) {
                chip.scrollToVisible(chip.bounds)
            }
        }
    }

    private func rebuildChips(for tabs: [TabEntry]) {
        chips.forEach { $0.removeFromSuperview() }
        chips.removeAll(keepingCapacity: true)
        dividers.forEach { $0.removeFromSuperview() }
        dividers = (0..<max(0, tabs.count - 1)).map { _ in
            let divider = NSView()
            divider.wantsLayer = true
            document.addSubview(divider, positioned: .below, relativeTo: dropIndicator)
            return divider
        }
        colorDividers()
        for tab in tabs {
            let chip = TabChipView(id: tab.id)
            chip.onSelect = { [weak self] in self?.delegate?.tabListDidSelect(tabId: tab.id) }
            chip.onClose  = { [weak self] in self?.delegate?.tabListDidRequestClose(tabId: tab.id) }
            document.addSubview(chip, positioned: .below, relativeTo: dropIndicator)
            chips.append(chip)
        }
    }

    // MARK: layout

    override func layout() {
        super.layout()
        layoutTabs()
    }

    private var tabWidth: CGFloat {
        guard !chips.isEmpty else { return Self.maxTabWidth }
        let available = scrollView.contentView.bounds.width - 2 * Self.inset
        let share = (available / CGFloat(chips.count)).rounded(.down)
        return min(Self.maxTabWidth, max(Self.minTabWidth, share))
    }

    private func layoutTabs() {
        let visible = scrollView.contentView.bounds.size
        let w = tabWidth
        let used = 2 * Self.inset + w * CGFloat(chips.count)
        document.frame = NSRect(x: 0, y: 0, width: max(used, visible.width), height: visible.height)
        for (i, chip) in chips.enumerated() {
            chip.frame = NSRect(x: Self.inset + CGFloat(i) * w, y: 0,
                                width: w, height: visible.height)
        }
        let dividerHeight: CGFloat = 16
        for (i, divider) in dividers.enumerated() {
            divider.frame = NSRect(x: Self.inset + CGFloat(i + 1) * w - 0.5,
                                   y: ((visible.height - dividerHeight) / 2).rounded(),
                                   width: 1, height: dividerHeight)
        }
    }

    // MARK: drop logic

    private func handleDragChanged(at point: NSPoint?) -> Bool {
        guard chips.count > 1, let point else {
            dropIndicator.isHidden = true
            return false
        }
        showDropIndicator(at: targetIndex(for: point.x))
        return true
    }

    private func handleDrop(at point: NSPoint, info: NSDraggingInfo) -> Bool {
        dropIndicator.isHidden = true
        guard chips.count > 1 else { return false }
        let index = targetIndex(for: point.x)
        guard let str = info.draggingPasteboard.string(forType: .kuddoTab),
              let uuid = UUID(uuidString: str) else { return false }
        delegate?.tabListDidReorderTab(tabId: uuid, toIndex: index)
        return true
    }

    /// The gap nearest `x`: left of a tab's midpoint inserts before it, right
    /// of it after.
    private func targetIndex(for x: CGFloat) -> Int {
        let raw = (x - Self.inset) / tabWidth
        return max(0, min(chips.count, Int(raw.rounded())))
    }

    /// A bar in the gap rather than the sidebar's highlighted slot: side by
    /// side, a slot-sized box reads as one more tab.
    private func showDropIndicator(at index: Int) {
        let x = Self.inset + CGFloat(index) * tabWidth
        dropIndicator.frame = NSRect(x: x - 1, y: 6, width: 2,
                                     height: max(0, document.bounds.height - 12))
        dropIndicator.isHidden = false
    }
}

/// A tab in the top strip.
final class TabChipView: TabItemView {
    override init(id: UUID) {
        super.init(id: id)
        addSubview(label)

        NSLayoutConstraint.activate([
            highlight.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            highlight.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            highlight.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            highlight.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),

            statusMark.centerXAnchor.constraint(equalTo: leadingAnchor, constant: 13),
            statusMark.centerYAnchor.constraint(equalTo: label.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 22),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: badgeLabel.leadingAnchor, constant: -6),

            badgeLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -9),
            badgeLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            closeBtn.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
            closeBtn.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func apply(_ entry: TabEntry, isActive: Bool, badge: String?) {
        let tip = [entry.process, entry.directory].compactMap { $0 }.joined(separator: " — ")
        let newTip = tip.isEmpty ? nil : tip
        if toolTip != newTip { toolTip = newTip }
        super.apply(entry, isActive: isActive, badge: badge)
    }
}
