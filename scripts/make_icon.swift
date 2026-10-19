import AppKit

func generateIcon() {
    let size = NSSize(width: 1024, height: 1024)
    let image = NSImage(size: size)
    
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return
    }
    
    // Background squircle
    let rect = CGRect(x: 64, y: 64, width: 896, height: 896)
    let clipPath = CGPath(roundedRect: rect, cornerWidth: 200, cornerHeight: 200, transform: nil)
    ctx.addPath(clipPath)
    ctx.clip()
    
    // Dark radial gradient
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let colors = [
        NSColor(red: 0.16, green: 0.04, blue: 0.05, alpha: 1.0).cgColor,
        NSColor(red: 0.05, green: 0.01, blue: 0.02, alpha: 1.0).cgColor
    ] as CFArray
    if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.0, 1.0]) {
        ctx.drawRadialGradient(gradient, startCenter: CGPoint(x: 512, y: 512), startRadius: 50, endCenter: CGPoint(x: 512, y: 512), endRadius: 500, options: [])
    }
    
    // Ambient red glow behind bell
    ctx.saveGState()
    let glowColors = [
        NSColor(red: 1.0, green: 0.2, blue: 0.2, alpha: 0.5).cgColor,
        NSColor(red: 1.0, green: 0.2, blue: 0.2, alpha: 0.0).cgColor
    ] as CFArray
    if let glowGradient = CGGradient(colorsSpace: colorSpace, colors: glowColors, locations: [0.0, 1.0]) {
        ctx.drawRadialGradient(glowGradient, startCenter: CGPoint(x: 512, y: 512), startRadius: 40, endCenter: CGPoint(x: 512, y: 512), endRadius: 360, options: [])
    }
    ctx.restoreGState()
    
    let symbolConfig = NSImage.SymbolConfiguration(pointSize: 460, weight: .bold)
    if let symbolImage = NSImage(systemSymbolName: "alarm.fill", accessibilityDescription: nil)?.withSymbolConfiguration(symbolConfig) {
        let symbolRect = CGRect(x: 232, y: 232, width: 560, height: 560)
        symbolImage.draw(in: symbolRect, from: .zero, operation: .sourceOver, fraction: 1.0)
    }
    
    // Inner border glow
    ctx.resetClip()
    let borderPath = CGPath(roundedRect: rect, cornerWidth: 200, cornerHeight: 200, transform: nil)
    ctx.addPath(borderPath)
    ctx.setLineWidth(16)
    ctx.setStrokeColor(NSColor(red: 1.0, green: 0.3, blue: 0.3, alpha: 0.8).cgColor)
    ctx.strokePath()
    
    image.unlockFocus()
    
    // Save to PNG
    if let tiffData = image.tiffRepresentation,
       let bitmap = NSBitmapImageRep(data: tiffData),
       let pngData = bitmap.representation(using: .png, properties: [:]) {
        let outputURL = URL(fileURLWithPath: "scripts/icon_1024.png")
        try? pngData.write(to: outputURL)
        print("Generated icon_1024.png successfully")
    }
}

generateIcon()
