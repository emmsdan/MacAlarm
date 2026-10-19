import AppKit

func generateDmgBackground() {
    let width: CGFloat = 660
    let height: CGFloat = 420
    let size = NSSize(width: width, height: height)
    let image = NSImage(size: size)
    
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return
    }
    
    // Background gradient
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bgColors = [
        NSColor(red: 0.12, green: 0.03, blue: 0.04, alpha: 1.0).cgColor,
        NSColor(red: 0.05, green: 0.01, blue: 0.02, alpha: 1.0).cgColor
    ] as CFArray
    if let gradient = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: height), end: CGPoint(x: width, y: 0), options: [])
    }
    
    // Ambient red radial glows
    ctx.saveGState()
    let glowColors = [
        NSColor(red: 1.0, green: 0.2, blue: 0.2, alpha: 0.35).cgColor,
        NSColor(red: 1.0, green: 0.2, blue: 0.2, alpha: 0.0).cgColor
    ] as CFArray
    if let glowGradient = CGGradient(colorsSpace: colorSpace, colors: glowColors, locations: [0.0, 1.0]) {
        ctx.drawRadialGradient(glowGradient, startCenter: CGPoint(x: 330, y: 240), startRadius: 20, endCenter: CGPoint(x: 330, y: 240), endRadius: 280, options: [])
    }
    ctx.restoreGState()
    
    // Title Text: "REAL ALARM"
    let titleAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 26, weight: .black),
        .foregroundColor: NSColor.white
    ]
    let titleString = NSAttributedString(string: "REAL ALARM FOR macOS", attributes: titleAttrs)
    let titleRect = CGRect(x: (width - titleString.size().width) / 2, y: height - 64, width: titleString.size().width, height: 36)
    titleString.draw(in: titleRect)
    
    // Subtitle Text: "Fullscreen Screen-Lock • Loud Ringing & Voice Announcements"
    let subAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 13, weight: .medium),
        .foregroundColor: NSColor(red: 1.0, green: 0.4, blue: 0.4, alpha: 0.9)
    ]
    let subString = NSAttributedString(string: "Fullscreen Screen-Lock • Rings & Sings Loud", attributes: subAttrs)
    let subRect = CGRect(x: (width - subString.size().width) / 2, y: height - 90, width: subString.size().width, height: 22)
    subString.draw(in: subRect)
    
    // Arrow in center: SF Symbol "arrow.right"
    let arrowConfig = NSImage.SymbolConfiguration(pointSize: 40, weight: .bold)
    if let arrow = NSImage(systemSymbolName: "arrow.right", accessibilityDescription: nil)?.withSymbolConfiguration(arrowConfig) {
        let arrowRect = CGRect(x: (width - 64) / 2, y: (height / 2) - 24, width: 64, height: 48)
        arrow.draw(in: arrowRect, from: .zero, operation: .sourceOver, fraction: 0.85)
    }
    
    // Bottom instruction: "Drag Alarm to Applications to install"
    let hintAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
        .foregroundColor: NSColor.white.withAlphaComponent(0.6)
    ]
    let hintString = NSAttributedString(string: "Drag Alarm into Applications to install", attributes: hintAttrs)
    let hintRect = CGRect(x: (width - hintString.size().width) / 2, y: 40, width: hintString.size().width, height: 22)
    hintString.draw(in: hintRect)
    
    image.unlockFocus()
    
    // Save PNG
    if let tiff = image.tiffRepresentation,
       let rep = NSBitmapImageRep(data: tiff),
       let png = rep.representation(using: .png, properties: [:]) {
        let out = URL(fileURLWithPath: "scripts/dmg_background.png")
        try? png.write(to: out)
        print("Generated dmg_background.png successfully")
    }
}

generateDmgBackground()
