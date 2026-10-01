import AppKit

/// Programmatic Kuddo app icon.
///
/// Rendered as a resolution-independent NSImage so it stays crisp at every
/// dock / cmd-tab / about-panel size without shipping a `.icns` resource.
package enum AppIcon {
    static func make() -> NSImage {
        let size = NSSize(width: 1024, height: 1024)
        let image = NSImage(size: size, flipped: false) { rect in
            draw(in: rect)
            return true
        }
        // Treat as a template-free regular icon (the dock should not tint it).
        image.isTemplate = false
        return image
    }

    /// Renders the icon at every size macOS expects in an `.iconset` bundle,
    /// writing PNGs into `directory`. The caller is expected to run `iconutil
    /// -c icns <directory>` to pack the result into a single `.icns`.
    package static func exportIconset(to directory: String) {
        let fm = FileManager.default
        let dir = URL(fileURLWithPath: directory)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)

        // (logical size in points, scale factor). macOS Icon Composer wants
        // both @1x and @2x for each canonical size.
        let entries: [(Int, Int)] = [
            (16, 1), (16, 2),
            (32, 1), (32, 2),
            (128, 1), (128, 2),
            (256, 1), (256, 2),
            (512, 1), (512, 2),
        ]

        let image = make()
        for (base, scale) in entries {
            let pixels = base * scale
            let suffix = scale == 1 ? "" : "@2x"
            let filename = "icon_\(base)x\(base)\(suffix).png"
            let url = dir.appendingPathComponent(filename)

            guard let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: pixels, pixelsHigh: pixels,
                bitsPerSample: 8, samplesPerPixel: 4,
                hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0
            ) else { continue }

            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
            NSGraphicsContext.restoreGraphicsState()

            guard let data = rep.representation(using: .png, properties: [:])
            else { continue }
            try? data.write(to: url)
        }
    }

    private static func draw(in rect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let s = rect.width // assume square

        // macOS icons inset content so the squircle doesn't fill the tile.
        // 1024-pt grid contents live in the central ~824-pt square.
        let inset: CGFloat = s * 0.09765625
        let tile = rect.insetBy(dx: inset, dy: inset)
        let corner: CGFloat = tile.width * 0.2237

        // The icon is a keycap: a k legend over the homing bar that F and J
        // carry, for a name picked because it types on the home row.

        // --- Keycap sides -----------------------------------------------------
        ctx.saveGState()
        NSBezierPath(roundedRect: tile, xRadius: corner, yRadius: corner).addClip()
        drawVertical(ctx, in: tile,
                     top: NSColor(srgbRed: 0.10, green: 0.11, blue: 0.13, alpha: 1),
                     bottom: NSColor(srgbRed: 0.05, green: 0.055, blue: 0.065, alpha: 1))
        ctx.restoreGState()

        // --- Top face ---------------------------------------------------------
        // Inset more at the bottom than the top, as a keycap seen slightly
        // from the front.
        let face = NSRect(x: tile.minX + tile.width * 0.075,
                          y: tile.minY + tile.height * 0.13,
                          width: tile.width * 0.85,
                          height: tile.height * 0.815)
        let faceCorner = corner * 0.8
        let facePath = NSBezierPath(roundedRect: face, xRadius: faceCorner, yRadius: faceCorner)

        // Its shadow onto the sides, then the face itself, lit from above.
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -tile.height * 0.012),
                      blur: tile.height * 0.03,
                      color: NSColor(white: 0, alpha: 0.6).cgColor)
        NSColor(srgbRed: 0.145, green: 0.155, blue: 0.18, alpha: 1).setFill()
        facePath.fill()
        ctx.restoreGState()

        ctx.saveGState()
        facePath.addClip()
        drawVertical(ctx, in: face,
                     top: NSColor(srgbRed: 0.20, green: 0.215, blue: 0.245, alpha: 1),
                     bottom: NSColor(srgbRed: 0.145, green: 0.155, blue: 0.18, alpha: 1))
        ctx.restoreGState()

        // --- Legend: k + homing bar ------------------------------------------
        // Classic phosphor console green.
        let accent = NSColor(srgbRed: 0.211, green: 0.965, blue: 0.286, alpha: 1)
        let accentSoft = NSColor(srgbRed: 0.211, green: 0.965, blue: 0.286, alpha: 0.25)

        // Geometric lowercase "k": a stem rising to the ascender, with the arm
        // and leg meeting it at one point. Drawn as a stroked path so the
        // weight stays consistent regardless of size.
        let xHeight    = face.height * 0.32
        let ascender   = xHeight * 1.5
        let glyphWidth = xHeight * 0.88
        let stroke     = face.height * 0.088

        // Centred, then lifted to leave room for the bar below.
        let kRect = NSRect(x: face.midX - glyphWidth / 2 + stroke * 0.1,
                           y: face.midY - ascender / 2 + face.height * 0.06,
                           width: glyphWidth, height: ascender)

        // Soft glow behind the legend for depth.
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: stroke * 1.6, color: accentSoft.cgColor)

        let kPath = makeKPath(in: kRect, xHeight: xHeight, strokeWidth: stroke)
        accent.setStroke()
        kPath.lineWidth = stroke
        kPath.lineCapStyle = .round
        kPath.lineJoinStyle = .round
        kPath.stroke()

        let barWidth = face.width * 0.22
        let barHeight = stroke * 0.55
        let bar = NSRect(x: face.midX - barWidth / 2,
                         y: face.minY + face.height * 0.14,
                         width: barWidth, height: barHeight)
        accent.withAlphaComponent(0.9).setFill()
        NSBezierPath(roundedRect: bar, xRadius: barHeight / 2, yRadius: barHeight / 2).fill()
        ctx.restoreGState()
    }

    /// Fills `rect` with a top-to-bottom gradient; the caller clips.
    private static func drawVertical(_ ctx: CGContext, in rect: NSRect,
                                     top: NSColor, bottom: NSColor) {
        let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [top.cgColor, bottom.cgColor] as CFArray,
            locations: [0, 1]
        )!
        ctx.drawLinearGradient(
            gradient,
            start: CGPoint(x: rect.midX, y: rect.maxY),
            end:   CGPoint(x: rect.midX, y: rect.minY),
            options: []
        )
    }

    /// Builds a stroked "k": the stem runs from the baseline to the top of
    /// `rect`, and the arm (up to the x-height) and the leg (down to the
    /// baseline) both leave the stem from the same point, a little below
    /// half the x-height.
    private static func makeKPath(in rect: NSRect, xHeight: CGFloat,
                                  strokeWidth: CGFloat) -> NSBezierPath {
        // Inset so the stroke sits fully inside `rect`.
        let r = rect.insetBy(dx: strokeWidth / 2, dy: strokeWidth / 2)
        let top = r.minY + xHeight - strokeWidth
        let joint = NSPoint(x: r.minX, y: r.minY + (top - r.minY) * 0.42)

        let path = NSBezierPath()
        path.move(to: NSPoint(x: r.minX, y: r.minY))
        path.line(to: NSPoint(x: r.minX, y: r.maxY))

        path.move(to: NSPoint(x: r.maxX, y: top))
        path.line(to: joint)
        path.line(to: NSPoint(x: r.maxX, y: r.minY))

        return path
    }
}
