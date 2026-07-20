#!/usr/bin/env swift
import AppKit
import Foundation

/// Renders Toast installer DMG backgrounds (1x + 2x PNG).
/// Usage: generate-dmg-background.swift <output-1x.png> [output-2x.png]

let args = CommandLine.arguments
guard args.count >= 2 else {
    fputs("Usage: \(args[0]) <output-1x.png> [output-2x.png]\n", stderr)
    exit(1)
}

func render(width: Int, height: Int) -> NSBitmapImageRep {
    guard let representation = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        fputs("Failed to create bitmap\n", stderr)
        exit(1)
    }

    // Draw in pixel coordinates matching the bitmap size.
    representation.size = NSSize(width: width, height: height)

    NSGraphicsContext.saveGraphicsState()
    guard let context = NSGraphicsContext(bitmapImageRep: representation) else {
        fputs("Failed to create graphics context\n", stderr)
        exit(1)
    }
    NSGraphicsContext.current = context
    defer { NSGraphicsContext.restoreGraphicsState() }

    // Scale factor relative to the 660×420 logical canvas.
    let s = CGFloat(width) / 660.0

    func px(_ v: CGFloat) -> CGFloat { v * s }

    let cream = NSColor(calibratedRed: 1.0, green: 0.98, blue: 0.94, alpha: 1)
    let yellow = NSColor(calibratedRed: 0.945, green: 0.718, blue: 0.071, alpha: 1)
    let orange = NSColor(calibratedRed: 0.871, green: 0.400, blue: 0.004, alpha: 1)
    let ink = NSColor(calibratedRed: 0.04, green: 0.04, blue: 0.04, alpha: 1)
    let muted = NSColor(calibratedRed: 0.32, green: 0.32, blue: 0.32, alpha: 1)
    let softYellow = NSColor(calibratedRed: 0.992, green: 0.929, blue: 0.725, alpha: 1)
    let cardFill = NSColor.white

    cream.setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()

    softYellow.setFill()
    NSRect(x: 0, y: CGFloat(height) - px(105), width: CGFloat(width), height: px(105)).fill()

    func font(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
        .systemFont(ofSize: px(size), weight: weight)
    }

    func drawText(
        _ string: String,
        font: NSFont,
        color: NSColor,
        in rect: NSRect,
        alignment: NSTextAlignment = .left
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byWordWrapping
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph,
        ]
        (string as NSString).draw(in: rect, withAttributes: attrs)
    }

    func roundedRect(_ rect: NSRect, radius: CGFloat, fill: NSColor) {
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        fill.setFill()
        path.fill()
    }

    func circle(_ center: NSPoint, radius: CGFloat, fill: NSColor) {
        let rect = NSRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        )
        fill.setFill()
        NSBezierPath(ovalIn: rect).fill()
    }

    drawText(
        "Install Toast",
        font: font(28, .bold),
        color: ink,
        in: NSRect(x: px(30), y: CGFloat(height) - px(58), width: px(400), height: px(34))
    )
    drawText(
        "Three quick steps · signed & notarized",
        font: font(13, .medium),
        color: muted,
        in: NSRect(x: px(30), y: CGFloat(height) - px(82), width: px(400), height: px(18))
    )

    // Step 1 pill — sits above the Finder icon row (icons ~ y 150–170).
    roundedRect(
        NSRect(x: px(175), y: CGFloat(height) - px(130), width: px(310), height: px(28)),
        radius: px(14),
        fill: yellow
    )
    drawText(
        "1  Drag Toast into Applications",
        font: font(13, .semibold),
        color: ink,
        in: NSRect(x: px(185), y: CGFloat(height) - px(124), width: px(290), height: px(18)),
        alignment: .center
    )

    // Arrow between Toast (~140,165) and Applications (~520,165) icon centers.
    let arrowY = CGFloat(height) - px(175)
    orange.setStroke()
    let arrow = NSBezierPath()
    arrow.lineWidth = px(3.5)
    arrow.lineCapStyle = .round
    arrow.move(to: NSPoint(x: px(210), y: arrowY))
    arrow.line(to: NSPoint(x: px(430), y: arrowY))
    arrow.stroke()

    let head = NSBezierPath()
    head.move(to: NSPoint(x: px(430), y: arrowY))
    head.line(to: NSPoint(x: px(414), y: arrowY + px(10)))
    head.line(to: NSPoint(x: px(414), y: arrowY - px(10)))
    head.close()
    orange.setFill()
    head.fill()

    // Bottom checkpoint cards (below icon labels).
    let cardY = px(22)
    let cardH = px(112)
    let cardW = px(290)
    let gap = px(20)
    let leftCard = NSRect(x: px(30), y: cardY, width: cardW, height: cardH)
    let rightCard = NSRect(x: px(30) + cardW + gap, y: cardY, width: cardW, height: cardH)

    roundedRect(leftCard, radius: px(14), fill: cardFill)
    roundedRect(rightCard, radius: px(14), fill: cardFill)

    func strokeCard(_ rect: NSRect) {
        let path = NSBezierPath(roundedRect: rect, xRadius: px(14), yRadius: px(14))
        NSColor(calibratedWhite: 0, alpha: 0.08).setStroke()
        path.lineWidth = px(1)
        path.stroke()
    }
    strokeCard(leftCard)
    strokeCard(rightCard)

    circle(NSPoint(x: leftCard.minX + px(22), y: leftCard.maxY - px(24)), radius: px(11), fill: orange)
    drawText(
        "2",
        font: font(12, .bold),
        color: .white,
        in: NSRect(x: leftCard.minX + px(14), y: leftCard.maxY - px(32), width: px(16), height: px(16)),
        alignment: .center
    )
    drawText(
        "Open Toast (recommended)",
        font: font(13, .semibold),
        color: ink,
        in: NSRect(x: leftCard.minX + px(40), y: leftCard.maxY - px(34), width: px(230), height: px(18))
    )
    drawText(
        "In Applications, double-click Toast to open. Notarized builds open without Gatekeeper workarounds.",
        font: font(11, .regular),
        color: muted,
        in: NSRect(x: leftCard.minX + px(16), y: leftCard.minY + px(14), width: cardW - px(32), height: px(56))
    )

    circle(NSPoint(x: rightCard.minX + px(22), y: rightCard.maxY - px(24)), radius: px(11), fill: orange)
    drawText(
        "3",
        font: font(12, .bold),
        color: .white,
        in: NSRect(x: rightCard.minX + px(14), y: rightCard.maxY - px(32), width: px(16), height: px(16)),
        alignment: .center
    )
    drawText(
        "Or Privacy & Security",
        font: font(13, .semibold),
        color: ink,
        in: NSRect(x: rightCard.minX + px(40), y: rightCard.maxY - px(34), width: px(230), height: px(18))
    )
    drawText(
        "Double-click Toast once (expect a warning). Then System Settings → Privacy & Security → Open Anyway.",
        font: font(11, .regular),
        color: muted,
        in: NSRect(x: rightCard.minX + px(16), y: rightCard.minY + px(14), width: cardW - px(32), height: px(56))
    )

    return representation
}

func writePNG(_ representation: NSBitmapImageRep, to path: String) {
    let url = URL(fileURLWithPath: path)
    guard let png = representation.representation(using: .png, properties: [:]) else {
        fputs("Failed to encode PNG\n", stderr)
        exit(1)
    }
    do {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try png.write(to: url)
        fputs("Wrote \(path)\n", stderr)
    } catch {
        fputs("Write failed: \(error)\n", stderr)
        exit(1)
    }
}

writePNG(render(width: 660, height: 420), to: args[1])
if args.count >= 3 {
    writePNG(render(width: 1320, height: 840), to: args[2])
}
