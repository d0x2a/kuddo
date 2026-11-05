import KuddoCore
import AppKit

/// What the sidebar and the top strip tell the window about its tabs.
protocol TabListDelegate: AnyObject {
    func tabListDidSelect(tabId: UUID)
    func tabListDidRequestClose(tabId: UUID)
    /// `toIndex` is the gap index in the pre-move array — i.e. 0 means
    /// "before the first tab," N means "after the last," k for 0<k<N
    /// means "between tab k-1 and tab k." Callers do their own
    /// remove-then-insert with the appropriate offset adjustment.
    func tabListDidReorderTab(tabId: UUID, toIndex: Int)
}

/// One tab as the sidebar and the top strip show it. `process` and
/// `directory` make the sidebar's line under the title and the strip's
/// tooltip, the directory already in display form (`~`-folded); a sidebar
/// row with neither centres its title alone.
struct TabEntry {
    enum Status { case working, waiting }

    var id: UUID
    var title: String
    var directory: String?
    /// The foreground command, by process name; nil at a shell prompt.
    var process: String?
    /// What the marker ahead of the title shows; nil shows nothing.
    var status: Status?
}

/// What the sidebar and the top strip have in common to look at.
enum TabListStyle {
    /// Tints the panel so it reads as distinct from the terminal beside it:
    /// a light theme's goes slightly darker than its background, while a
    /// dark theme's goes slightly lighter (pushing a dark bg further toward
    /// black just muddies it). The shift is small on purpose.
    static func panelColor() -> NSColor {
        let theme = ThemeStore.currentTheme
        let bg = theme.background
        // Blend toward black (light themes) or white (dark themes) by a small
        // amount so the panel separates without looking like a different color.
        let amount: Float = 0.06
        let target: Float = theme.appearance == .dark ? 1.0 : 0.0
        func mix(_ c: Float) -> CGFloat { CGFloat(c + (target - c) * amount) }
        return NSColor(
            srgbRed: mix(bg.x), green: mix(bg.y), blue: mix(bg.z),
            alpha: CGFloat(bg.w))
    }

    /// The line between a panel and the terminal. The system separator reads
    /// as too bright over a dark terminal, so it comes from the theme
    /// background: nearly blended on a dark theme, a little stronger on a
    /// light one so it stays perceptible.
    static func separatorColor() -> NSColor {
        let theme = ThemeStore.currentTheme
        let bg = theme.background
        let isDark = theme.appearance == .dark
        let amount: Float = isDark ? 0.05 : 0.06
        let target: Float = isDark ? 1.0 : 0.0
        func mix(_ c: Float) -> CGFloat { CGFloat(c + (target - c) * amount) }
        return NSColor(srgbRed: mix(bg.x), green: mix(bg.y), blue: mix(bg.z),
                       alpha: CGFloat(bg.w))
    }

    /// ⌘1–8 address the first eight tabs; ⌘9 always jumps to the last one.
    static func badge(at idx: Int, of count: Int) -> String? {
        shortcutDigit(at: idx, of: count).map { "⌘\($0)" }
    }

    /// The digit that goes with ⌘ to reach the tab at `idx`, if one does.
    static func shortcutDigit(at idx: Int, of count: Int) -> String? {
        if idx < 8 { return "\(idx + 1)" }
        if idx == count - 1 { return "9" }
        return nil
    }

    /// The marker ahead of a tab's title. Orange for a tab that wants you,
    /// the way the ⌘K hub marks one that rang. Working is quieter on purpose
    /// — it asks nothing — and static: a spinner per busy tab would keep the
    /// main thread drawing for as long as any agent worked.
    static func statusMark(_ status: TabEntry.Status) -> (image: NSImage?, tint: NSColor) {
        let symbol: String
        let tint: NSColor
        let label: String
        switch status {
        case .waiting: (symbol, tint, label) = ("circle.fill", .systemOrange, "Waiting for you")
        case .working: (symbol, tint, label) = ("circle.dotted", .secondaryLabelColor, "Working")
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)?
            .withSymbolConfiguration(statusConfiguration)
        return (image, tint)
    }

    /// The marker with its colour baked in, for a menu item, which won't tint
    /// an image the way an image view does. A tab without one gets a blank of
    /// the same size, so every title in the menu starts at the same x.
    static func statusMenuImage(_ status: TabEntry.Status?) -> NSImage? {
        guard let status else {
            let size = statusMark(.waiting).image?.size ?? NSSize(width: 9, height: 9)
            return NSImage(size: size)
        }
        let tint = statusMark(status).tint
        // Applied over the size, not in place of it: a configuration given
        // on its own replaces the one before, size included.
        return statusMark(status).image?.withSymbolConfiguration(
            statusConfiguration.applying(NSImage.SymbolConfiguration(paletteColors: [tint])))
    }

    private static let statusConfiguration = NSImage.SymbolConfiguration(pointSize: 8, weight: .bold)
}

extension NSPasteboard.PasteboardType {
    static let kuddoTab = NSPasteboard.PasteboardType("com.d0x2a.kuddo.tab")
}

/// Layout constants shared between the row views and the drop-indicator math.
private enum SidebarMetrics {
    /// Two lines: the tab's title over its working directory.
    static let rowHeight: CGFloat = 40
    static let topInset: CGFloat = 4
}

final class SidebarView: NSView {
    weak var delegate: TabListDelegate?

    private let scrollView = NSScrollView()
    private let document = TabDropView()
    private let stack = NSStackView()
    private var rows: [TabRowView] = []
    private let dropIndicator = NSView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        applyThemeBackground()
        NotificationCenter.default.addObserver(
            self, selector: #selector(themeDidChange),
            name: .kuddoThemeDidChange, object: nil)

        stack.orientation = .vertical
        stack.spacing = 0
        stack.alignment = .leading
        stack.edgeInsets = NSEdgeInsets(
            top: SidebarMetrics.topInset, left: 0,
            bottom: SidebarMetrics.topInset, right: 0
        )
        stack.translatesAutoresizingMaskIntoConstraints = false

        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            stack.topAnchor.constraint(equalTo: document.topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: document.bottomAnchor),
        ])

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.documentView = document
        addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            document.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
        ])

        dropIndicator.wantsLayer = true
        dropIndicator.layer?.backgroundColor = NSColor.controlAccentColor
            .withAlphaComponent(0.18).cgColor
        dropIndicator.layer?.borderColor = NSColor.controlAccentColor
            .withAlphaComponent(0.55).cgColor
        dropIndicator.layer?.borderWidth = 1
        dropIndicator.layer?.cornerRadius = 4
        dropIndicator.isHidden = true
        document.addSubview(dropIndicator)

        document.registerForDraggedTypes([.kuddoTab])
        document.onDragChanged = { [weak self] point in
            self?.handleDragChanged(at: point) ?? false
        }
        document.onDragPerform = { [weak self] point, info in
            self?.handleDrop(at: point, info: info) ?? false
        }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func themeDidChange() { applyThemeBackground() }

    /// See `TabListStyle.panelColor`.
    private func applyThemeBackground() {
        layer?.backgroundColor = TabListStyle.panelColor().cgColor
    }

    func update(tabs: [TabEntry], activeId: UUID?) {
        // Only rebuild when the tabs themselves change. Titles change on every
        // prompt and refreshSidebar() runs for each one — tearing down the row
        // under the pointer would cancel the press AppKit is tracking, losing
        // the click or the drag about to start. Selecting a tab refreshes the
        // sidebar too, so a row has to survive its own onSelect.
        if rows.map(\.id) != tabs.map(\.id) {
            rebuildRows(for: tabs)
        }
        for (idx, tab) in tabs.enumerated() {
            rows[idx].apply(tab,
                            isActive: tab.id == activeId,
                            badge: TabListStyle.badge(at: idx, of: tabs.count))
        }
    }

    private func rebuildRows(for tabs: [TabEntry]) {
        rows.forEach { $0.removeFromSuperview() }
        rows.removeAll(keepingCapacity: true)
        for tab in tabs {
            let row = TabRowView(id: tab.id)
            row.onSelect = { [weak self] in self?.delegate?.tabListDidSelect(tabId: tab.id) }
            row.onClose  = { [weak self] in self?.delegate?.tabListDidRequestClose(tabId: tab.id) }
            row.translatesAutoresizingMaskIntoConstraints = false
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            rows.append(row)
        }
        // Keep the indicator above the new rows.
        document.addSubview(dropIndicator)
    }

    // MARK: drop logic

    private func handleDragChanged(at point: NSPoint?) -> Bool {
        guard rows.count > 1, let point else {
            dropIndicator.isHidden = true
            return false
        }
        let index = targetIndex(for: point.y)
        showDropIndicator(at: index)
        return true
    }

    private func handleDrop(at point: NSPoint, info: NSDraggingInfo) -> Bool {
        dropIndicator.isHidden = true
        guard rows.count > 1 else { return false }
        let index = targetIndex(for: point.y)
        guard let str = info.draggingPasteboard.string(forType: .kuddoTab),
              let uuid = UUID(uuidString: str) else { return false }
        delegate?.tabListDidReorderTab(tabId: uuid, toIndex: index)
        return true
    }

    /// Maps a y-coordinate inside the document view to a gap index. Each row
    /// is split at its midpoint: above the midpoint inserts before that row;
    /// below inserts after.
    private func targetIndex(for y: CGFloat) -> Int {
        let h = SidebarMetrics.rowHeight
        let inset = SidebarMetrics.topInset
        let raw = (y - inset) / h
        let idx = Int(raw.rounded())
        return max(0, min(rows.count, idx))
    }

    private func showDropIndicator(at index: Int) {
        let h = SidebarMetrics.rowHeight
        let inset = SidebarMetrics.topInset
        let y = inset + CGFloat(index) * h
        let width = document.bounds.width - 8
        dropIndicator.frame = NSRect(x: 4, y: y, width: max(0, width), height: h)
        dropIndicator.isHidden = false
    }
}

/// Flipped document view that also serves as the drag-and-drop destination,
/// for the sidebar and the top strip both. Forwards drag callbacks via
/// closures so the destination logic can live next to the layout it controls.
final class TabDropView: NSView {
    override var isFlipped: Bool { true }

    /// Returns whether the drop is acceptable at this point. `nil` means
    /// the drag exited the view.
    var onDragChanged: ((NSPoint?) -> Bool)?
    /// Returns whether the drop was accepted and consumed.
    var onDragPerform: ((NSPoint, NSDraggingInfo) -> Bool)?

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let pt = convert(sender.draggingLocation, from: nil)
        return (onDragChanged?(pt) ?? false) ? .move : []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let pt = convert(sender.draggingLocation, from: nil)
        return (onDragChanged?(pt) ?? false) ? .move : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        _ = onDragChanged?(nil)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pt = convert(sender.draggingLocation, from: nil)
        return onDragPerform?(pt, sender) ?? false
    }
}

/// A tab in the sidebar or the top strip. Selects on press, drags to
/// reorder, swaps its ⌘-number for a close button on hover, and carries the
/// status marker. Subclasses place the parts; `label` they add themselves,
/// since the sidebar stacks it over a second line and the strip doesn't.
class TabItemView: NSView, NSDraggingSource {
    let id: UUID
    let highlight = NSView()
    let label = NSTextField(labelWithString: "")
    /// Ahead of the title: working, waiting on you, or nothing.
    let statusMark = NSImageView()
    let badgeLabel = NSTextField(labelWithString: "")
    let closeBtn = NSButton()
    private var status: TabEntry.Status?
    private var isActive = false
    private var badgeText: String?
    private var hover = false { didSet { refreshAppearance() } }
    private var trackingArea: NSTrackingArea?

    /// Press origin in window coordinates, set in mouseDown and cleared when
    /// the press ends or turns into a drag. Distance from it is what separates
    /// a click from a reorder. Comfortably above trackpad click jitter: at 4pt
    /// an ordinary click would spawn a drag session.
    private var pressDownLocation: NSPoint?
    private static let dragThreshold: CGFloat = 10

    var onSelect: (() -> Void)?
    var onClose:  (() -> Void)?

    init(id: UUID) {
        self.id = id
        super.init(frame: .zero)

        wantsLayer = true

        // Inset + rounded background for the active/hover highlight. Sits
        // behind the label/badge/close button so they read on top of it.
        highlight.wantsLayer = true
        highlight.layer?.cornerRadius = 5
        highlight.translatesAutoresizingMaskIntoConstraints = false
        addSubview(highlight)

        label.font = NSFont.systemFont(ofSize: 12)
        label.lineBreakMode = .byTruncatingMiddle
        label.maximumNumberOfLines = 1
        label.usesSingleLineMode = true
        label.translatesAutoresizingMaskIntoConstraints = false
        // The title is the only thing that may shrink: a long one must
        // truncate rather than push the badge past the trailing edge.
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        statusMark.imageScaling = .scaleNone
        statusMark.translatesAutoresizingMaskIntoConstraints = false
        statusMark.isHidden = true

        // Secondary, not tertiary: at a quarter opacity the shortcut was too
        // faint to read against the tinted panel.
        badgeLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        badgeLabel.textColor = .secondaryLabelColor
        badgeLabel.alignment = .right
        badgeLabel.translatesAutoresizingMaskIntoConstraints = false
        badgeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        badgeLabel.setContentHuggingPriority(.required, for: .horizontal)

        closeBtn.title = ""
        closeBtn.image = NSImage(systemSymbolName: "xmark",
                                 accessibilityDescription: "Close tab")
        closeBtn.imagePosition = .imageOnly
        closeBtn.isBordered = false
        closeBtn.controlSize = .small
        closeBtn.target = self
        closeBtn.action = #selector(closeAction(_:))
        closeBtn.isHidden = true     // hover-only
        closeBtn.translatesAutoresizingMaskIntoConstraints = false

        addSubview(statusMark)
        addSubview(badgeLabel)
        addSubview(closeBtn)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area = trackingArea { removeTrackingArea(area) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { hover = true }
    override func mouseExited(with event: NSEvent)  { hover = false }

    // MARK: click / drag disambiguation

    override func mouseDown(with event: NSEvent) {
        pressDownLocation = event.locationInWindow
        // Select on press, the way NSTableView and the Finder sidebar do.
        // Waiting for mouseUp meant a press that drifted past the drag
        // threshold became a drag session instead — and a drag session
        // swallows mouseUp, so the click selected nothing and the tab you
        // aimed at stayed in the background.
        onSelect?()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = pressDownLocation else { return }
        let dx = event.locationInWindow.x - start.x
        let dy = event.locationInWindow.y - start.y
        let dist2 = dx * dx + dy * dy
        guard dist2 >= Self.dragThreshold * Self.dragThreshold else { return }

        pressDownLocation = nil          // consume — this press is a drag now.
        beginTabDrag(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        pressDownLocation = nil
    }

    private func beginTabDrag(with event: NSEvent) {
        let item = NSPasteboardItem()
        item.setString(id.uuidString, forType: .kuddoTab)

        let dragItem = NSDraggingItem(pasteboardWriter: item)
        dragItem.setDraggingFrame(bounds, contents: snapshot())

        beginDraggingSession(with: [dragItem], event: event, source: self)
    }

    private func snapshot() -> NSImage {
        let rep = bitmapImageRepForCachingDisplay(in: bounds)!
        cacheDisplay(in: bounds, to: rep)
        let img = NSImage(size: bounds.size)
        img.addRepresentation(rep)
        return img
    }

    // MARK: NSDraggingSource

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .move
    }

    /// Dim the source while a drag is in flight so the drop indicator reads
    /// clearly even when it overlaps neighboring slots.
    func draggingSession(_ session: NSDraggingSession,
                         willBeginAt screenPoint: NSPoint) {
        alphaValue = 0.3
    }

    func draggingSession(_ session: NSDraggingSession,
                         endedAt screenPoint: NSPoint,
                         operation: NSDragOperation) {
        alphaValue = 1.0
    }

    // MARK: appearance

    /// Updates the tab in place. Views outlive a refresh so that a press in
    /// flight isn't cancelled by an unrelated title change.
    func apply(_ entry: TabEntry, isActive: Bool, badge: String?) {
        let badgeString = badge ?? ""
        if label.stringValue != entry.title { label.stringValue = entry.title }
        if badgeLabel.stringValue != badgeString { badgeLabel.stringValue = badgeString }
        if status != entry.status {
            status = entry.status
            applyStatus()
        }
        self.isActive = isActive
        self.badgeText = badge
        refreshAppearance()
    }

    /// See `TabListStyle.statusMark`.
    private func applyStatus() {
        guard let status else {
            statusMark.isHidden = true
            statusMark.image = nil
            return
        }
        let mark = TabListStyle.statusMark(status)
        statusMark.image = mark.image
        statusMark.contentTintColor = mark.tint
        statusMark.isHidden = false
    }

    private func refreshAppearance() {
        if isActive {
            highlight.layer?.backgroundColor = NSColor.unemphasizedSelectedContentBackgroundColor.cgColor
            highlight.isHidden = false
            label.textColor = .labelColor
        } else if hover {
            highlight.layer?.backgroundColor = NSColor.unemphasizedSelectedContentBackgroundColor
                .withAlphaComponent(0.5).cgColor
            highlight.isHidden = false
            label.textColor = .labelColor
        } else {
            highlight.isHidden = true
            label.textColor = .secondaryLabelColor
        }
        closeBtn.isHidden = !hover
        badgeLabel.isHidden = hover || badgeText == nil
    }

    @objc private func closeAction(_ sender: Any)  { onClose?() }
}

/// A tab's row in the sidebar: its title over the foreground process and the
/// directory.
final class TabRowView: TabItemView {
    private let processLabel = NSTextField(labelWithString: "")
    private let directoryLabel = NSTextField(labelWithString: "")
    /// The line under the title: the foreground process, then the directory.
    private let detail = NSStackView()
    /// Title over detail. Hidden views drop out of a stack's layout, so a row
    /// with nothing to put under its title centres the title alone.
    private let lines = NSStackView()

    override init(id: UUID) {
        super.init(id: id)

        // Truncated at the head, not the middle like the title: the end of a
        // path is where you are, while its start is nearly always `~/source/`
        // or the like, which tells one tab from another not at all.
        directoryLabel.font = NSFont.systemFont(ofSize: 11)
        directoryLabel.textColor = .secondaryLabelColor
        directoryLabel.lineBreakMode = .byTruncatingHead
        directoryLabel.maximumNumberOfLines = 1
        directoryLabel.usesSingleLineMode = true
        directoryLabel.isHidden = true
        directoryLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // The process name never truncates — "cla…" names nothing — so a long
        // path gives way to it. Heavier than the path so the two read as two
        // things without a separator between them.
        processLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        processLabel.textColor = .secondaryLabelColor
        processLabel.maximumNumberOfLines = 1
        processLabel.usesSingleLineMode = true
        processLabel.isHidden = true
        processLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        processLabel.setContentHuggingPriority(.required, for: .horizontal)

        detail.orientation = .horizontal
        detail.alignment = .firstBaseline
        detail.spacing = 5
        detail.detachesHiddenViews = true
        detail.addArrangedSubview(processLabel)
        detail.addArrangedSubview(directoryLabel)
        detail.isHidden = true
        detail.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        lines.orientation = .vertical
        lines.alignment = .leading
        lines.spacing = 1
        lines.detachesHiddenViews = true
        lines.translatesAutoresizingMaskIntoConstraints = false
        lines.addArrangedSubview(label)
        lines.addArrangedSubview(detail)
        lines.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(lines)

        NSLayoutConstraint.activate([
            highlight.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5),
            highlight.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5),
            highlight.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            highlight.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),

            // A gutter the marker sits in, kept on rows without one so every
            // title starts at the same x.
            statusMark.centerXAnchor.constraint(equalTo: leadingAnchor, constant: 15),
            statusMark.centerYAnchor.constraint(equalTo: label.centerYAnchor),
            lines.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            lines.centerYAnchor.constraint(equalTo: centerYAnchor),
            lines.trailingAnchor.constraint(lessThanOrEqualTo: badgeLabel.leadingAnchor, constant: -6),

            badgeLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            badgeLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            closeBtn.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            closeBtn.centerYAnchor.constraint(equalTo: centerYAnchor),

            heightAnchor.constraint(equalToConstant: SidebarMetrics.rowHeight),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func apply(_ entry: TabEntry, isActive: Bool, badge: String?) {
        setText(entry.process, of: processLabel)
        setText(entry.directory, of: directoryLabel)
        let hasDetail = !processLabel.isHidden || !directoryLabel.isHidden
        if detail.isHidden == hasDetail { detail.isHidden = !hasDetail }
        super.apply(entry, isActive: isActive, badge: badge)
    }

    private func setText(_ text: String?, of field: NSTextField) {
        let string = text ?? ""
        guard field.stringValue != string else { return }
        field.stringValue = string
        field.isHidden = string.isEmpty
    }
}
