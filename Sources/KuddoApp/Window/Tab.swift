import KuddoCore
import AppKit
import Foundation

package final class Tab {
    package let id = UUID()
    let terminalView: TerminalView
    /// Display title for the sidebar — typically the cwd's basename, falls
    /// back to the shell's OSC title or "Kuddo". Starts as the name of the
    /// directory the tab opens in.
    package internal(set) var displayTitle: String = "Kuddo" {
        didSet { if displayTitle != oldValue { TabDirectory.shared.setNeedsNotify() } }
    }
    /// Which profile started this tab, kept so session restore can bring it
    /// back on the same one. nil means the default profile at the time the
    /// tab was made — deliberately not resolved to an id here, so a tab
    /// opened with ⌘T follows the user's later change of default rather than
    /// pinning itself to whatever was default when it opened.
    let profileId: UUID?
    /// Raised when the child rang the bell or posted an OSC notification while
    /// this tab wasn't the one being looked at, and cleared when it is selected.
    /// Only the ⌘K hub reads it today — it is what puts the bell marker on a
    /// row — but it is the state the sidebar would need for the same badge.
    var wantsAttention: Bool = false
    /// A bell's banner, held back briefly in case a notification escape that
    /// says more comes with it (`MainWindowController.bellGrace`).
    var pendingBell: DispatchWorkItem?
    /// When this tab last posted a notification escape, so a bell rung just
    /// after it doesn't post a second banner.
    var lastNotificationAt: Date?
    /// Set when this tab shows a tmux window rather than a shell of its own.
    /// Closing it closes the tmux window; it is not restored across launches,
    /// because the tmux server may be gone and reattaching is the user's call.
    var tmuxWindowID: String?

    /// The tab's session, once it has one. A tab's shell starts the first time
    /// the tab is shown, so one restored in the background has none until it
    /// is selected; `TabObserver`s hear when it arrives.
    package var session: Session? { terminalView.session }

    init(initialCwd: String?, profile: Profile? = nil) {
        let v = TerminalView(frame: .zero)
        // Default to the user's home dir when nothing else is provided.
        // Without this, the shell inherits the parent process's CWD —
        // which for an app launched from /Applications is `/`.
        v.initialCwd = initialCwd ?? profile?.startDirectory() ?? NSHomeDirectory()
        v.profile = profile
        self.terminalView = v
        self.profileId = profile?.id
        // Named after where it opens before its shell has said anything. The
        // shell — and the cwd the title follows — only starts once the tab is
        // first shown, so a tab restored in the background would otherwise
        // read "Kuddo" until it was clicked.
        if let name = Self.basename(of: v.initialCwd) { displayTitle = name }
    }

    /// How a directory names a tab: its last component, `~` for home.
    static func basename(of cwd: String?) -> String? {
        guard let cwd, !cwd.isEmpty else { return nil }
        if cwd == "/" { return "/" }
        if cwd == NSHomeDirectory() { return "~" }
        return (cwd as NSString).lastPathComponent
    }

    /// The tab's name at the head of a notification banner. Coding agents put
    /// a status mark ahead of their title, which tells nothing in a banner
    /// that only appears once they have stopped, so it comes off the front:
    ///
    /// - Claude Code: "✳ name" while it waits, a spinner frame while it works.
    /// - omp: "π > name" — its own mark, then ">" idle, "!" waiting on you,
    ///   ":" or a spinner frame while working.
    ///
    /// A leading emoji stays: that is someone's choice of name.
    var notificationName: String { Self.notificationName(of: displayTitle) }

    static func notificationName(of title: String) -> String {
        let s = Array(title.unicodeScalars)
        let start: Int
        if s.count > 4, s[0] == "π", s[1] == " ", s[3] == " ",
           !s[2].properties.isAlphabetic, !s[2].properties.isWhitespace,
           s[2].properties.numericType == nil {
            start = 4
        } else if s.count > 2, s[1] == " ",
                  s[0].properties.generalCategory == .otherSymbol || s[0] == "·",
                  !s[0].properties.isEmojiPresentation {
            start = 2
        } else {
            return title
        }
        var rest = String.UnicodeScalarView()
        rest.append(contentsOf: s[start...])
        let name = String(rest).trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? title : name
    }
}
