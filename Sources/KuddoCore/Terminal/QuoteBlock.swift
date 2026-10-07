import Foundation

/// Finds the quoted passage under the pointer, for ⌘-click to copy whole.
///
/// Claude Code draws a markdown blockquote behind a bar: `▎` in a column of
/// its own, a space, then the text. The bar is on every row of the quote —
/// the rows its own word wrap made, and the blank lines between paragraphs —
/// so it is the boundary the way colour is for a run: the quote is every
/// neighbouring row with a bar in the same column. The text inside is mostly
/// in the default colour, which is why a run never found it.
///
/// What gets copied is the text without the bar, put back together. A row the
/// program wrapped rejoins the one above it by the rules a coloured run's rows
/// do — a space where the wrap dropped one, none inside a word too long for a
/// row. A bar on its own is a blank line between paragraphs. Anything else — a
/// heading, a list item, a line that stopped short of the edge — starts a line
/// of its own.
///
/// It comes back as a `ColorRun`, so it is marked and confirmed the way a run
/// is: the same faint tint, the same sheet with its character count.
package enum QuoteBlockDetector {
    /// U+258E LEFT ONE QUARTER BLOCK, Claude Code's quote bar.
    package static let bar: Unicode.Scalar = "\u{258E}"

    private typealias Grid = ColorRunDetector.Grid
    private typealias Span = ColorRunDetector.Span

    /// The quote under `coord`, or nil when no bar opens the row there, the
    /// pointer is left of the bar, or there's nothing but bars.
    package static func quote(at coord: (col: Int, row: Int),
                              snapshot: TerminalSnapshot) -> ColorRun? {
        guard coord.row >= 0, coord.row < snapshot.rows,
              coord.col >= 0, coord.col < snapshot.cols else { return nil }
        let grid = Grid(snapshot: snapshot)
        guard let barCol = barColumn(grid, coord.row), coord.col >= barCol else { return nil }

        var first = coord.row, last = coord.row
        while first > 0, barColumn(grid, first - 1) == barCol { first -= 1 }
        while last + 1 < snapshot.rows, barColumn(grid, last + 1) == barCol { last += 1 }

        // Each row's text past the bar, or nil for a row with only the bar.
        let lines: [Span?] = (first...last).map { row in
            guard let end = grid.contentEnd(row), end > barCol,
                  let start = (barCol + 1...end).first(where: { !grid.isBlank(row, $0) })
            else { return nil }
            return Span(row: row, lo: start, hi: end)
        }
        let spans = lines.compactMap { $0 }
        guard spans.contains(where: grid.hasWord) else { return nil }
        let reach = spans.map(\.hi).max() ?? 0
        // Where text starts: past the bar and the one space after it. Text
        // further in than that is indented, and keeps its indent.
        let margin = barCol + 2

        var text = ""
        var above: Span?
        var paragraphBreak = false
        for line in lines {
            guard let line else {
                paragraphBreak = !text.isEmpty
                above = nil
                continue
            }
            if let above, !opensItem(grid, line),
               grid.runsOn(from: above.row, end: above.hi, to: line.row, start: line.lo) {
                if !grid.continuesWord(from: above, to: line, reach: reach) { text.append(" ") }
            } else {
                if !text.isEmpty { text.append(paragraphBreak ? "\n\n" : "\n") }
                text.append(String(repeating: " ", count: max(0, line.lo - margin)))
            }
            text.append(grid.text(line))
            above = line
            paragraphBreak = false
        }

        return ColorRun(segments: spans.map { .init(row: $0.row, col: $0.lo, length: $0.hi - $0.lo + 1) },
                        text: text,
                        color: textColor(grid, spans))
    }

    /// The column of the bar that opens `row`, if one does: the row's first
    /// mark, with a space or the edge after it.
    private static func barColumn(_ grid: Grid, _ row: Int) -> Int? {
        guard let col = grid.contentStart(row), grid.cell(row, col).scalar == bar,
              col + 1 == grid.snapshot.cols || grid.isBlank(row, col + 1) else { return nil }
        return col
    }

    /// Does the line open with a list marker — `-`, `*`, `+`, `•`, `1.`, `1)` —
    /// and so start an item of its own, however near the edge the row above
    /// it ended?
    private static func opensItem(_ grid: Grid, _ line: Span) -> Bool {
        var word = ""
        var col = line.lo
        while col <= line.hi, !grid.isBlank(line.row, col) {
            word.unicodeScalars.append(grid.cell(line.row, col).scalar)
            col += 1
        }
        guard col <= line.hi else { return false }      // a marker has text after it
        if ["-", "*", "+", "•"].contains(word) { return true }
        guard let mark = word.last, mark == "." || mark == ")" else { return false }
        let number = word.dropLast()
        return !number.isEmpty && number.allSatisfy { $0.isASCII && $0.isNumber }
    }

    /// The colour most of the quote's text is in, for the tint and the sheet's
    /// preview: a bold heading or a coloured word inside shouldn't set it.
    private static func textColor(_ grid: Grid, _ spans: [Span]) -> PackedColor {
        var counts: [PackedColor: Int] = [:]
        for span in spans {
            for col in span.lo...span.hi where !grid.isBlank(span.row, col) {
                counts[grid.cell(span.row, col).fg, default: 0] += 1
            }
        }
        return counts.max { $0.value < $1.value }?.key ?? grid.cell(spans[0].row, spans[0].lo).fg
    }
}
