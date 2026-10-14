// Renders Intfy/Assets.xcassets/AppIcon.appiconset/icon-1024.png. Run: swift scripts/make-icon.swift
import AppKit

let size = 1024
let cg = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                   space: CGColorSpace(name: CGColorSpace.sRGB)!,
                   bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: false)
let rect = NSRect(x: 0, y: 0, width: size, height: size)
NSGradient(starting: NSColor(red: 0.20, green: 0.64, blue: 0.58, alpha: 1),
           ending: NSColor(red: 0.12, green: 0.36, blue: 0.47, alpha: 1))!.draw(in: rect, angle: -90)

let config = NSImage.SymbolConfiguration(pointSize: 560, weight: .semibold)
    .applying(.init(paletteColors: [.white]))
let bell = NSImage(systemSymbolName: "bell.fill", accessibilityDescription: nil)!.withSymbolConfiguration(config)!
let b = bell.size
bell.draw(in: NSRect(x: (CGFloat(size) - b.width) / 2, y: (CGFloat(size) - b.height) / 2, width: b.width, height: b.height))
NSGraphicsContext.current = nil

let out = URL(fileURLWithPath: "Intfy/Assets.xcassets/AppIcon.appiconset/icon-1024.png")
let rep = NSBitmapImageRep(cgImage: cg.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: out)
print("wrote \(out.path)")
