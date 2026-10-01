import Foundation

/// `~/Library/Application Support/Kuddo/`: settings, saved state, triggers,
/// profiles, imported themes and the shell-integration wrappers. Created on
/// first access.
package enum AppSupport {
    package static let directory: URL? = {
        let fm = FileManager.default
        guard let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        let dir = base.appendingPathComponent("Kuddo", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            adoptLegacy(from: base.appendingPathComponent("mTerm", isDirectory: true), into: dir)
        }
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Kuddo shipped as mTerm, which kept the same files under
    /// `Application Support/mTerm/`. The first launch after the rename copies
    /// the user's own files across — copied, not moved, so an mTerm that is
    /// still running, or gets reinstalled, keeps working from its own folder.
    /// The shell wrappers and scratch history stay behind: Kuddo rewrites the
    /// wrappers on launch, and the history files belong to shells mTerm started.
    private static func adoptLegacy(from legacy: URL, into dir: URL) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: legacy.path) else { return }
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        for name in ["settings.json", "state.json", "triggers.json", "profiles", "themes"] {
            let from = legacy.appendingPathComponent(name)
            guard fm.fileExists(atPath: from.path) else { continue }
            try? fm.copyItem(at: from, to: dir.appendingPathComponent(name))
        }
    }
}
