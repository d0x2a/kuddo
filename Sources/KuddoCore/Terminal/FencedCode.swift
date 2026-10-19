import Foundation

/// Finds the fenced code block under the pointer, for ⌘-click to copy the
/// code in it.
///
/// A program that prints markdown as it is — Codex, `cat` of a README, a
/// diff, a prompt someone pasted — shows a code block with its fences: a row
/// opening with ``` or ~~~, usually with a language after it, the code, and a
/// row with the fence alone. Unlike a run's colour or a command's shape, that
/// boundary is stated in the text, so the block is exactly the rows between a
/// fence and the one that closes it. Claude Code is not one of these
/// programs: it draws the code highlighted and leaves the fences out.
///
/// What gets copied is the code without its fences, ready for psql or an
/// editor, with the opening fence's indent taken off every line: a block
/// inside a list item copies flush left and keeps the indent within it. A row
/// the terminal wrapped rejoins the row it continues. A row the program broke
/// itself stays broken: in code there is no telling a wrapper's break from
/// the author's.
///
/// Only the rows on screen can be read, so a block whose top has scrolled off
/// shows a closing fence with no opener above it. Pairing from the top would
/// take that closer for an opener and the prose under it for code. A fence
/// that names a language gives it away: a closer never names one, so one
/// arriving while a bare fence is open means the bare fence was a closer.
///
/// It comes back as a `ColorRun`, so it is marked and confirmed the way a run
/// is: the same faint tint, the same sheet with its character count.
package enum FencedCodeDetector {
    private typealias Grid = ColorRunDetector.Grid
    private typealias Span = ColorRunDetector.Span

    private struct Fence {
        let row: Int
        let col: Int
        /// ` or ~. A block closes on a fence of the same mark.
        let mark: Unicode.Scalar
        /// A block closes on a fence at least as long as the one that opened
        /// it, so ```` can hold a ``` as code.
        let length: Int
        /// Anything after the fence, a language usually. A closer has none.
        let hasInfo: Bool
    }

    /// The code in the block under `coord`, or nil when the pointer isn't on
    /// a block's rows, is left of its fence, or the block is empty or runs
    /// off the screen before it closes.
    package static func block(at coord: (col: Int, row: Int),
                              snapshot: TerminalSnapshot) -> ColorRun? {
        guard coord.row >= 0, coord.row < snapshot.rows,
              coord.col >= 0, coord.col < snapshot.cols else { return nil }
        let grid = Grid(snapshot: snapshot)
        guard let block = blocks(grid).first(where: { $0.open.row <= coord.row && coord.row <= $0.close.row }),
              coord.col >= block.open.col else { return nil }
        let (open, close) = block

        var lines: [String] = []
        var spans: [Span] = []
        var row = open.row + 1
        while row < close.row {
            // The rows the terminal wrapped this one onto are the same line.
            var last = row
            while last + 1 < close.row, isWrapped(snapshot, last) { last += 1 }
            var line = ""
            for r in row...last {
                // Up to the edge on a row that wrapped, where a space may be
                // the line's own; to its last mark on the one that didn't.
                let end = r < last ? snapshot.cols - 1 : (grid.contentEnd(r) ?? -1)
                for col in stride(from: 0, through: end, by: 1) where !grid.cell(r, col).isContinuation {
                    line.unicodeScalars.append(grid.cell(r, col).scalar)
                }
                if let lo = grid.contentStart(r), let hi = grid.contentEnd(r) {
                    spans.append(Span(row: r, lo: lo, hi: hi))
                }
            }
            let indent = min(open.col, line.prefix(while: { $0 == " " }).count)
            lines.append(String(line.dropFirst(indent))
                .replacingOccurrences(of: " +$", with: "", options: .regularExpression))
            row = last + 1
        }
        guard !spans.isEmpty else { return nil }

        return ColorRun(segments: spans.map { .init(row: $0.row, col: $0.lo, length: $0.hi - $0.lo + 1) },
                        text: lines.joined(separator: "\n"),
                        color: grid.dominantForeground(spans))
    }

    /// Every block on screen, opening fence to closing fence, top to bottom.
    /// Inside a block, a fence that can't close it is code.
    private static func blocks(_ grid: Grid) -> [(open: Fence, close: Fence)] {
        var found: [(open: Fence, close: Fence)] = []
        var open: Fence?
        for row in 0..<grid.snapshot.rows {
            guard let fence = fence(grid, row) else { continue }
            guard let opener = open else {
                open = fence
                continue
            }
            if fence.mark == opener.mark, fence.length >= opener.length, !fence.hasInfo {
                found.append((opener, fence))
                open = nil
            } else if fence.hasInfo, !opener.hasInfo {
                open = fence                 // the bare one closed a block above the screen
            }
        }
        return found
    }

    /// The fence `row` opens with, if it opens with one: three or more of the
    /// same mark as the row's first text, at the start of a line rather than
    /// on a row a longer line wrapped onto.
    private static func fence(_ grid: Grid, _ row: Int) -> Fence? {
        let cols = grid.snapshot.cols
        guard row == 0 || !isWrapped(grid.snapshot, row - 1),
              let start = grid.contentStart(row) else { return nil }
        let mark = grid.cell(row, start).scalar
        guard mark == "`" || mark == "~" else { return nil }
        var end = start
        while end < cols, grid.cell(row, end).scalar == mark { end += 1 }
        guard end - start >= 3 else { return nil }
        let info = (end..<cols).filter { !grid.isBlank(row, $0) }
        // "```x``` is inline code" opens with three backticks too. A backtick
        // fence's info string can't hold one.
        if mark == "`", info.contains(where: { grid.cell(row, $0).scalar == "`" }) { return nil }
        return Fence(row: row, col: start, mark: mark, length: end - start, hasInfo: !info.isEmpty)
    }

    private static func isWrapped(_ snapshot: TerminalSnapshot, _ row: Int) -> Bool {
        snapshot.rowWrapped.indices.contains(row) && snapshot.rowWrapped[row]
    }
}
