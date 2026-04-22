#!/bin/bash
# Generate Resources/AppIcon.icns with per-size native renders.
#
# Three templates, selected by canvas size:
#   - 256 / 512 / 1024  → Full pixel "JOINT / CHIEFS" wordmark (website-hero tie)
#   - 64 / 128          → Pixel "JC" monogram (wordmark illegible at this scale)
#   - 16 / 32           → Clean "JC" in SF Pro Heavy (pixel cells become sub-pixel)
#
# Apple's icon design guidance: small sizes should be simpler than large ones —
# never just a downscale. Downscaling the full wordmark produces blurry
# illegible artwork at 64px and below, which is exactly the sizes that
# render in the Dock and Finder's default grid.
#
# All templates share the warm-charcoal squircle chrome, the agentBgDeep →
# agentBgPanel vertical gradient, and a subtle inner rim highlight. The
# wordmark uses Joint Chiefs blue (#0285ff).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RESOURCES_DIR="$REPO_ROOT/Resources"
ICONSET_DIR="$RESOURCES_DIR/AppIcon.iconset"
ICNS_PATH="$RESOURCES_DIR/AppIcon.icns"

mkdir -p "$ICONSET_DIR"

SWIFT_RENDERER="$(mktemp /tmp/jc-icon-render.XXXX.swift)"
trap 'rm -f "$SWIFT_RENDERER"' EXIT

cat > "$SWIFT_RENDERER" <<'SWIFT_EOF'
import AppKit
import CoreGraphics
import Foundation

guard CommandLine.arguments.count >= 3 else {
    FileHandle.standardError.write(Data("usage: render <size> <output>\n".utf8))
    exit(64)
}
let size = CGFloat(Double(CommandLine.arguments[1]) ?? 0)
let outputPath = CommandLine.arguments[2]
guard size > 0 else { exit(64) }

// Palette — Agentdeck dark app surfaces.
let agentBgDeep    = NSColor(red: 20/255.0, green: 17/255.0, blue: 16/255.0, alpha: 1)
let agentBgPanel   = NSColor(red: 26/255.0, green: 22/255.0, blue: 20/255.0, alpha: 1)
let agentBgDeepHi  = NSColor(red: 42/255.0, green: 38/255.0, blue: 36/255.0, alpha: 1)
let agentBrandBlue = NSColor(red: 2/255.0,  green: 133/255.0, blue: 255/255.0, alpha: 1)

// Pixel font — 5 cells wide × 7 rows, matching the jointchiefs.ai hero.
let pixelFont: [Character: [String]] = [
    "J": [".####", "....#", "....#", "....#", "....#", "#...#", ".###."],
    "O": [".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
    "I": ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "#####"],
    "N": ["#...#", "##..#", "#.#.#", "#.#.#", "#..##", "#...#", "#...#"],
    "T": ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.."],
    "C": [".####", "#....", "#....", "#....", "#....", "#....", ".####"],
    "H": ["#...#", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
    "E": ["#####", "#....", "#....", "####.", "#....", "#....", "#####"],
    "F": ["#####", "#....", "#....", "####.", "#....", "#....", "#...."],
    "S": [".####", "#....", "#....", ".###.", "....#", "....#", "####."]
]

// Draw chrome that scales with canvas.
func drawChrome() {
    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let radius = size * 0.219  // 224 on 1024 canvas
    let squircle = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    NSGraphicsContext.current?.saveGraphicsState()
    squircle.addClip()
    let gradient = NSGradient(colors: [agentBgDeepHi, agentBgPanel, agentBgDeep])!
    gradient.draw(in: rect, angle: 270)
    // Rim highlight — only on canvases where it will actually render.
    if size >= 64 {
        let inset: CGFloat = size >= 256 ? 4 : 2
        let strokeW: CGFloat = size >= 256 ? 3 : 1.5
        let inner = rect.insetBy(dx: inset, dy: inset)
        let rim = NSBezierPath(roundedRect: inner, xRadius: max(0, radius - inset), yRadius: max(0, radius - inset))
        rim.lineWidth = strokeW
        NSColor(white: 1, alpha: 0.07).setStroke()
        rim.stroke()
    }
    NSGraphicsContext.current?.restoreGraphicsState()
}

// Draw pixel text — scales with canvas. `lines` may contain newlines.
// anchor/hAlign/vAlign/textAlign control block position and internal
// line alignment.
enum HAlign { case left, center, right }
enum VAlign { case top, middle, bottom }

func drawPixelText(
    _ text: String,
    cellSize: CGFloat,
    color: NSColor,
    anchor: NSPoint,
    hAlign: HAlign = .center,
    vAlign: VAlign = .middle,
    textAlign: HAlign? = nil
) {
    let tAlign = textAlign ?? hAlign
    let lines = text.split(separator: "\n").map { String($0) }
    let rows = 7
    let lineGap = 1
    let letterGap = 1
    var lineCells: [Int] = []
    var maxCells = 0
    for line in lines {
        var w = 0
        for ch in line { w += (pixelFont[ch]?.first?.count ?? 5) + letterGap }
        if !line.isEmpty { w -= letterGap }
        lineCells.append(w)
        maxCells = max(maxCells, w)
    }
    let totalHeightCells = lines.count * rows + (lines.count - 1) * lineGap
    let blockW = CGFloat(maxCells) * cellSize
    let blockH = CGFloat(totalHeightCells) * cellSize

    let blockLeft: CGFloat = {
        switch hAlign {
        case .left:   return anchor.x
        case .center: return anchor.x - blockW / 2
        case .right:  return anchor.x - blockW
        }
    }()
    let blockBottom: CGFloat = {
        switch vAlign {
        case .top:    return anchor.y - blockH
        case .middle: return anchor.y - blockH / 2
        case .bottom: return anchor.y
        }
    }()

    color.setFill()
    var lineTopY = blockBottom + blockH
    for (idx, line) in lines.enumerated() {
        let lineW = CGFloat(lineCells[idx]) * cellSize
        let lineLeft: CGFloat = {
            switch tAlign {
            case .left:   return blockLeft
            case .center: return blockLeft + (blockW - lineW) / 2
            case .right:  return blockLeft + (blockW - lineW)
            }
        }()
        var x = lineLeft
        for ch in line {
            guard let glyph = pixelFont[ch] else { x += cellSize * 5; continue }
            for (rowIdx, row) in glyph.enumerated() {
                for (colIdx, c) in row.enumerated() where c == "#" {
                    let px = x + CGFloat(colIdx) * cellSize
                    let py = lineTopY - CGFloat(rowIdx + 1) * cellSize
                    NSRect(x: px, y: py, width: cellSize, height: cellSize).fill()
                }
            }
            x += CGFloat((glyph.first?.count ?? 5) + letterGap) * cellSize
        }
        lineTopY -= CGFloat(rows + lineGap) * cellSize
    }
}

// Draw clean "JC" type — used at the smallest canvas sizes.
func drawTypeMark() {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let fontSize = size * 0.55
    let font = NSFont.systemFont(ofSize: fontSize, weight: .heavy)
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: agentBrandBlue,
        .tracking: -fontSize * 0.04,
        .paragraphStyle: paragraph
    ]
    let text = NSAttributedString(string: "JC", attributes: attrs)
    let sz = text.size()
    text.draw(at: NSPoint(
        x: (size - sz.width) / 2,
        y: (size - sz.height) / 2 - size * 0.03  // optical-center nudge
    ))
}

// Select template based on canvas size.
func drawForeground() {
    if size >= 256 {
        // Full wordmark — top-left justified, matching P02 on 1024.
        // Proportional inset: anchor at (140,140) on 1024 scales with size.
        let cellSize = 18 * (size / 1024)
        let anchorInset = 140 * (size / 1024)
        drawPixelText(
            "JOINT\nCHIEFS",
            cellSize: cellSize,
            color: agentBrandBlue,
            anchor: NSPoint(x: anchorInset, y: size - anchorInset),
            hAlign: .left, vAlign: .top, textAlign: .left
        )
    } else if size >= 64 {
        // Pixel "JC" monogram — bigger cells, centered.
        let cellSize = size * 0.10   // JC (11 cells wide) occupies ~75% of canvas
        drawPixelText(
            "JC",
            cellSize: cellSize,
            color: agentBrandBlue,
            anchor: NSPoint(x: size / 2, y: size / 2),
            hAlign: .center, vAlign: .middle, textAlign: .center
        )
    } else {
        // Type-only "JC" for 32 and 16 canvases.
        drawTypeMark()
    }
}

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
drawChrome()
drawForeground()
image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("failed to encode PNG\n".utf8))
    exit(1)
}
try png.write(to: URL(fileURLWithPath: outputPath))
SWIFT_EOF

echo "==> Rendering per-size natively"

render() {
    local dim="$1"
    local name="$2"
    swift "$SWIFT_RENDERER" "$dim" "$ICONSET_DIR/$name"
    echo "    ${name} (${dim}×${dim})"
}

# iconset slots — each one rendered at its actual display resolution.
render 16   "icon_16x16.png"
render 32   "icon_16x16@2x.png"
render 32   "icon_32x32.png"
render 64   "icon_32x32@2x.png"
render 128  "icon_128x128.png"
render 256  "icon_128x128@2x.png"
render 256  "icon_256x256.png"
render 512  "icon_256x256@2x.png"
render 512  "icon_512x512.png"
render 1024 "icon_512x512@2x.png"

echo "==> Packaging AppIcon.icns"
iconutil -c icns "$ICONSET_DIR" -o "$ICNS_PATH"

echo "==> Done"
echo "    $ICNS_PATH"
