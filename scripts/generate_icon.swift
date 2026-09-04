import Foundation
import AppKit
import CoreGraphics

func createSwarmDeckIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    
    guard let context = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }
    
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)
    
    let scale = size / 1024.0
    
    // 1. Draw macOS App Icon Squircle (824x824 centered in 1024x1024)
    let squircleMargin = 100.0 * scale
    let squircleSize = size - (2.0 * squircleMargin)
    let squircleRect = NSRect(x: squircleMargin, y: squircleMargin, width: squircleSize, height: squircleSize)
    let cornerRadius = 185.0 * scale
    let squirclePath = NSBezierPath(roundedRect: squircleRect, xRadius: cornerRadius, yRadius: cornerRadius)
    
    // Drop shadow under squircle
    context.saveGState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.4)
    shadow.shadowOffset = NSSize(width: 0, height: -12.0 * scale)
    shadow.shadowBlurRadius = 24.0 * scale
    shadow.set()
    NSColor(calibratedRed: 0.08, green: 0.10, blue: 0.15, alpha: 1.0).setFill()
    squirclePath.fill()
    context.restoreGState()
    
    // Squircle Background Gradient
    context.saveGState()
    squirclePath.addClip()
    
    let bgGradient = NSGradient(
        starting: NSColor(calibratedRed: 0.12, green: 0.14, blue: 0.20, alpha: 1.0),
        ending: NSColor(calibratedRed: 0.06, green: 0.08, blue: 0.12, alpha: 1.0)
    )
    bgGradient?.draw(in: squircleRect, angle: -45)
    
    // Subtle inner border
    let borderPath = NSBezierPath(roundedRect: squircleRect.insetBy(dx: 1.5 * scale, dy: 1.5 * scale), xRadius: cornerRadius - 1.5 * scale, yRadius: cornerRadius - 1.5 * scale)
    borderPath.lineWidth = 3.0 * scale
    NSColor(calibratedWhite: 1.0, alpha: 0.12).setStroke()
    borderPath.stroke()
    
    // 2. Terminal Window Header Bar (macOS Window style)
    let headerHeight = 80.0 * scale
    let headerY = squircleRect.maxY - headerHeight - (40.0 * scale)
    let headerRect = NSRect(x: squircleRect.minX + (45.0 * scale), y: headerY, width: squircleSize - (90.0 * scale), height: headerHeight)
    let windowCardRect = NSRect(x: squircleRect.minX + (45.0 * scale), y: squircleRect.minY + (45.0 * scale), width: squircleSize - (90.0 * scale), height: squircleSize - (90.0 * scale))
    
    let windowCardPath = NSBezierPath(roundedRect: windowCardRect, xRadius: 40.0 * scale, yRadius: 40.0 * scale)
    NSColor(calibratedRed: 0.03, green: 0.04, blue: 0.06, alpha: 0.85).setFill()
    windowCardPath.fill()
    
    let windowBorder = NSBezierPath(roundedRect: windowCardRect.insetBy(dx: 1.0 * scale, dy: 1.0 * scale), xRadius: 39.0 * scale, yRadius: 39.0 * scale)
    windowBorder.lineWidth = 1.5 * scale
    NSColor(calibratedWhite: 1.0, alpha: 0.08).setStroke()
    windowBorder.stroke()
    
    // 3. Mini Window Control Dots (Close, Minimize, Zoom)
    let dotRadius = 11.0 * scale
    let dotY = headerRect.midY
    let dotStartX = headerRect.minX + (35.0 * scale)
    let dotSpacing = 28.0 * scale
    
    let dotColors: [NSColor] = [
        NSColor(calibratedRed: 1.00, green: 0.37, blue: 0.34, alpha: 1.0), // Red
        NSColor(calibratedRed: 1.00, green: 0.74, blue: 0.18, alpha: 1.0), // Yellow
        NSColor(calibratedRed: 0.15, green: 0.79, blue: 0.25, alpha: 1.0)  // Green
    ]
    
    for (i, color) in dotColors.enumerated() {
        let center = NSPoint(x: dotStartX + (CGFloat(i) * dotSpacing), y: dotY)
        let dotPath = NSBezierPath(ovalIn: NSRect(x: center.x - dotRadius, y: center.y - dotRadius, width: dotRadius * 2, height: dotRadius * 2))
        color.setFill()
        dotPath.fill()
    }
    
    // Header divider line
    let divider = NSBezierPath()
    divider.move(to: NSPoint(x: windowCardRect.minX, y: headerRect.minY))
    divider.line(to: NSPoint(x: windowCardRect.maxX, y: headerRect.minY))
    divider.lineWidth = 1.0 * scale
    NSColor(calibratedWhite: 1.0, alpha: 0.06).setStroke()
    divider.stroke()
    
    // 4. Prompt Glyph ">_"
    let promptFontSize = 140.0 * scale
    let font = NSFont.monospacedSystemFont(ofSize: promptFontSize, weight: .bold)
    let promptAttributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor(calibratedRed: 0.0, green: 0.96, blue: 0.83, alpha: 1.0) // Neon Cyan
    ]
    let promptString = NSAttributedString(string: ">_", attributes: promptAttributes)
    let promptX = windowCardRect.minX + (50.0 * scale)
    let promptY = windowCardRect.maxY - (260.0 * scale)
    promptString.draw(at: NSPoint(x: promptX, y: promptY))
    
    // 5. Swarm Agent Nodes (Constellation representing 4 parallel agents)
    let nodes: [(point: NSPoint, color: NSColor, radius: CGFloat)] = [
        (NSPoint(x: windowCardRect.minX + 220.0 * scale, y: windowCardRect.minY + 230.0 * scale),
         NSColor(calibratedRed: 0.72, green: 0.45, blue: 1.00, alpha: 1.0), 32.0 * scale), // Claude (Purple)
        (NSPoint(x: windowCardRect.minX + 430.0 * scale, y: windowCardRect.minY + 310.0 * scale),
         NSColor(calibratedRed: 0.20, green: 0.88, blue: 0.55, alpha: 1.0), 28.0 * scale), // Aider (Green)
        (NSPoint(x: windowCardRect.minX + 570.0 * scale, y: windowCardRect.minY + 160.0 * scale),
         NSColor(calibratedRed: 1.00, green: 0.58, blue: 0.20, alpha: 1.0), 26.0 * scale), // Antigravity (Orange)
        (NSPoint(x: windowCardRect.minX + 380.0 * scale, y: windowCardRect.minY + 110.0 * scale),
         NSColor(calibratedRed: 0.30, green: 0.70, blue: 1.00, alpha: 1.0), 22.0 * scale)  // Shell (Cyan)
    ]
    
    // Constellation lines connecting nodes
    let linePath = NSBezierPath()
    linePath.lineWidth = 3.0 * scale
    NSColor(calibratedWhite: 1.0, alpha: 0.18).setStroke()
    for i in 0..<nodes.count {
        let nextIndex = (i + 1) % nodes.count
        linePath.move(to: nodes[i].point)
        linePath.line(to: nodes[nextIndex].point)
    }
    linePath.move(to: nodes[0].point)
    linePath.line(to: nodes[2].point)
    linePath.stroke()
    
    // Draw Node Orbs with Outer Glow
    for node in nodes {
        // Outer glow
        context.saveGState()
        let nodeGlow = NSShadow()
        nodeGlow.shadowColor = node.color.withAlphaComponent(0.8)
        nodeGlow.shadowOffset = .zero
        nodeGlow.shadowBlurRadius = 18.0 * scale
        nodeGlow.set()
        
        let nodePath = NSBezierPath(ovalIn: NSRect(
            x: node.point.x - node.radius,
            y: node.point.y - node.radius,
            width: node.radius * 2,
            height: node.radius * 2
        ))
        node.color.setFill()
        nodePath.fill()
        context.restoreGState()
        
        // Inner white highlight
        let innerRadius = node.radius * 0.4
        let innerHighlight = NSBezierPath(ovalIn: NSRect(
            x: node.point.x - innerRadius,
            y: node.point.y + (node.radius * 0.1),
            width: innerRadius * 2,
            height: innerRadius * 2
        ))
        NSColor(calibratedWhite: 1.0, alpha: 0.5).setFill()
        innerHighlight.fill()
    }
    
    context.restoreGState()
    
    image.unlockFocus()
    return image
}

func savePNG(image: NSImage, targetURL: URL, pixelSize: Int) throws {
    guard let _ = image.tiffRepresentation else {
        throw NSError(domain: "IconGenerator", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to get TIFF representation"])
    }
    
    let scaledRep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )
    
    guard let outputRep = scaledRep else {
        throw NSError(domain: "IconGenerator", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create bitmap rep"])
    }
    
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: outputRep)
    image.draw(in: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize),
               from: .zero,
               operation: .copy,
               fraction: 1.0)
    NSGraphicsContext.restoreGraphicsState()
    
    guard let pngData = outputRep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "IconGenerator", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to generate PNG data"])
    }
    
    try pngData.write(to: targetURL)
}

let fm = FileManager.default
let iconsetDir = URL(fileURLWithPath: "Resources/AppIcon.iconset")
try? fm.removeItem(at: iconsetDir)
try fm.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

let iconSizes: [(name: String, size: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

print("Generating SwarmDeck icon assets...")
let baseImage = createSwarmDeckIcon(size: 1024)

for item in iconSizes {
    let fileURL = iconsetDir.appendingPathComponent(item.name)
    try savePNG(image: baseImage, targetURL: fileURL, pixelSize: item.size)
    print("  ✓ Rendered \(item.name) (\(item.size)x\(item.size))")
}

let icnsPath = "Resources/AppIcon.icns"
let proc = Process()
proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
proc.arguments = ["-c", "icns", "Resources/AppIcon.iconset", "-o", icnsPath]
try proc.run()
proc.waitUntilExit()

if proc.terminationStatus == 0 {
    print("✓ Successfully created \(icnsPath)")
} else {
    print("✗ iconutil failed with status \(proc.terminationStatus)")
    exit(proc.terminationStatus)
}
