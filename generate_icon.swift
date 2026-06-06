// Generates AppIcon.icns matching the current OXO game aesthetic:
// dark CRT bezel, circular phosphor screen, amber O + blue-white X.
// Run: swift generate_icon.swift

import CoreGraphics
import ImageIO
import Foundation

let size: CGFloat = 1024

func makeIcon(size: CGFloat) -> CGImage {
    let cs   = CGColorSpaceCreateDeviceRGB()
    let ctx  = CGContext(data: nil, width: Int(size), height: Int(size),
                         bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.translateBy(x: 0, y: size); ctx.scaleBy(x: 1, y: -1)
    let r = CGRect(x: 0, y: 0, width: size, height: size)

    // Background is transparent — only the phosphor circle is opaque.
    // macOS squircle-clips the icon in the Dock; transparent corners show through.

    let cx = size / 2, cy = size / 2

    // Phosphor circle — fills the full icon square edge to edge
    let screenR: CGFloat = size * 0.47

    // ── Phosphor screen (dark + very faint ambient glow) ─────────────────────
    ctx.setFillColor(CGColor(red: 0.01, green: 0.015, blue: 0.04, alpha: 1))
    ctx.fillEllipse(in: CGRect(x: cx - screenR, y: cy - screenR,
                                width: screenR * 2, height: screenR * 2))

    // Clip subsequent drawing to the circle
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: cx - screenR, y: cy - screenR,
                               width: screenR * 2, height: screenR * 2))
    ctx.clip()

    // ── Dot-matrix board (11×11, dotSp ∝ size) ───────────────────────────────
    let dotSp: CGFloat = size * 0.088
    let dotR:  CGFloat = dotSp * 0.27
    let bx: CGFloat = cx - 5 * dotSp
    let by: CGFloat = cy - 5 * dotSp

    func dotAt(col: Int, row: Int) -> CGPoint {
        CGPoint(x: bx + CGFloat(col) * dotSp, y: by + CGFloat(row) * dotSp)
    }

    func drawDot(at p: CGPoint, r: CGFloat, red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        ctx.setFillColor(CGColor(red: red, green: green, blue: blue, alpha: alpha))
        ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
    }

    // Dividers: dim blue-grey at cols 3, 7 and rows 3, 7
    for i in 0...10 {
        for dv in [3, 7] {
            let vp = dotAt(col: dv, row: i)
            let hp = dotAt(col: i, row: dv)
            for (p, _) in [(vp, 0), (hp, 0)] {
                drawDot(at: p, r: dotR * 2.5, red: 0.10, green: 0.18, blue: 0.40, alpha: 0.25)
                drawDot(at: p, r: dotR,       red: 0.30, green: 0.45, blue: 0.70, alpha: 0.55)
            }
        }
    }

    // X mark (blue-white) in top-left cell (col 0-2, row 0-2)
    // 3×3 X pattern: (0,0),(0,2),(1,1),(2,0),(2,2)
    let xCell = [(0,0),(0,2),(1,1),(2,0),(2,2)]
    for (r, c) in xCell {
        let p = dotAt(col: c, row: r)
        drawDot(at: p, r: dotR * 3.0, red: 0.10, green: 0.30, blue: 0.80, alpha: 0.15)
        drawDot(at: p, r: dotR * 1.6, red: 0.22, green: 0.50, blue: 0.90, alpha: 0.45)
        drawDot(at: p, r: dotR,       red: 0.70, green: 0.88, blue: 1.00, alpha: 0.95)
    }

    // O mark (amber) in centre cell (col 4-6, row 4-6)
    // 3×3 O pattern: border of square
    let oCell = [(0,0),(0,1),(0,2),(1,0),(1,2),(2,0),(2,1),(2,2)]
    for (r, c) in oCell {
        let p = dotAt(col: 4 + c, row: 4 + r)
        drawDot(at: p, r: dotR * 3.0, red: 0.80, green: 0.30, blue: 0.01, alpha: 0.18)
        drawDot(at: p, r: dotR * 1.6, red: 0.80, green: 0.40, blue: 0.04, alpha: 0.50)
        drawDot(at: p, r: dotR,       red: 1.00, green: 0.72, blue: 0.12, alpha: 0.97)
    }

    // X mark (blue-white) in bottom-right cell (col 8-10, row 8-10)
    for (r, c) in xCell {
        let p = dotAt(col: 8 + c, row: 8 + r)
        drawDot(at: p, r: dotR * 3.0, red: 0.10, green: 0.30, blue: 0.80, alpha: 0.15)
        drawDot(at: p, r: dotR * 1.6, red: 0.22, green: 0.50, blue: 0.90, alpha: 0.45)
        drawDot(at: p, r: dotR,       red: 0.70, green: 0.88, blue: 1.00, alpha: 0.95)
    }

    // ── Rim glow (blue-white bleed at screen edge) ────────────────────────────
    ctx.restoreGState()
    let rimWidth: CGFloat = screenR * 0.06
    if let gradient = CGGradient(colorsSpace: cs,
        colors: [CGColor(red: 0.20, green: 0.40, blue: 0.90, alpha: 0.18),
                 CGColor(red: 0.10, green: 0.20, blue: 0.60, alpha: 0.00)] as CFArray,
        locations: [0.0, 1.0]) {
        ctx.saveGState()
        ctx.addEllipse(in: CGRect(x: cx - screenR, y: cy - screenR,
                                   width: screenR * 2, height: screenR * 2))
        ctx.addEllipse(in: CGRect(x: cx - screenR + rimWidth, y: cy - screenR + rimWidth,
                                   width: (screenR - rimWidth) * 2, height: (screenR - rimWidth) * 2))
        ctx.clip(using: .evenOdd)
        ctx.drawRadialGradient(gradient,
            startCenter: CGPoint(x: cx, y: cy), startRadius: screenR - rimWidth,
            endCenter:   CGPoint(x: cx, y: cy), endRadius:   screenR,
            options: [])
        ctx.restoreGState()
    }

    return ctx.makeImage()!
}

// Write PNG, then convert to icns via sips + iconutil
let img  = makeIcon(size: 1024)
let dest = URL(fileURLWithPath: "icon_tmp.png")
let dst  = CGImageDestinationCreateWithURL(dest as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(dst, img, nil)
CGImageDestinationFinalize(dst)

// Apple's required iconset filenames and their pixel sizes.
// Name format: icon_<logical>x<logical>[@2x].png
let iconsetSlots: [(name: String, px: Int)] = [
    ("icon_16x16",        16),
    ("icon_16x16@2x",     32),
    ("icon_32x32",        32),
    ("icon_32x32@2x",     64),
    ("icon_128x128",     128),
    ("icon_128x128@2x",  256),
    ("icon_256x256",     256),
    ("icon_256x256@2x",  512),
    ("icon_512x512",     512),
    ("icon_512x512@2x", 1024),
]

let fm = FileManager.default
try? fm.createDirectory(atPath: "AppIcon.iconset", withIntermediateDirectories: true)

for slot in iconsetSlots {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
    task.arguments = ["-z", "\(slot.px)", "\(slot.px)", "icon_tmp.png",
                      "--out", "AppIcon.iconset/\(slot.name).png"]
    try? task.run(); task.waitUntilExit()
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", "AppIcon.iconset", "-o", "AppIcon.icns"]
try? iconutil.run(); iconutil.waitUntilExit()

try? fm.removeItem(atPath: "icon_tmp.png")
try? fm.removeItem(atPath: "AppIcon.iconset")
print("AppIcon.icns generated.")
