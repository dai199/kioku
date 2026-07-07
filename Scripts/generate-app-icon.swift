#!/usr/bin/env swift
// Kiokuのアプリアイコンを生成する。
// 使い方: swift Scripts/generate-app-icon.swift <出力iconsetディレクトリ>
// デザイン: インディゴのグラデーション角丸 ＋ 白い吹き出し ＋ 「記」

import AppKit

let canvas: CGFloat = 1024

func drawIcon() {
    // 背景の角丸正方形（macOSアイコングリッド: 1024中824、角丸185）
    let bgRect = NSRect(x: 100, y: 100, width: 824, height: 824)
    let bg = NSBezierPath(roundedRect: bgRect, xRadius: 185, yRadius: 185)
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.44, green: 0.38, blue: 0.93, alpha: 1),
        NSColor(calibratedRed: 0.23, green: 0.20, blue: 0.70, alpha: 1),
    ])!
    gradient.draw(in: bg, angle: -90)

    // 白い吹き出し（本体＋左下のしっぽ）
    let bubbleRect = NSRect(x: 272, y: 340, width: 480, height: 390)
    let bubble = NSBezierPath(roundedRect: bubbleRect, xRadius: 100, yRadius: 100)
    let tail = NSBezierPath()
    tail.move(to: NSPoint(x: 360, y: 360))
    tail.line(to: NSPoint(x: 310, y: 240))
    tail.line(to: NSPoint(x: 480, y: 345))
    tail.close()
    NSColor.white.setFill()
    bubble.fill()
    tail.fill()

    // 「K」
    let font = NSFont.systemFont(ofSize: 320, weight: .heavy)
    let text = NSAttributedString(string: "K", attributes: [
        .font: font,
        .foregroundColor: NSColor(calibratedRed: 0.28, green: 0.24, blue: 0.78, alpha: 1),
    ])
    let size = text.size()
    text.draw(at: NSPoint(
        x: bubbleRect.midX - size.width / 2,
        y: bubbleRect.midY - size.height / 2
    ))
}

func renderPNG(px: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: px, height: px)
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: CGFloat(px) / canvas, y: CGFloat(px) / canvas)
    drawIcon()
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Kioku.iconset"
let iconsetURL = URL(fileURLWithPath: outputPath)
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

let entries: [(size: Int, scale: Int)] = [
    (16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2),
    (256, 1), (256, 2), (512, 1), (512, 2),
]
for entry in entries {
    let px = entry.size * entry.scale
    let name = entry.scale == 1
        ? "icon_\(entry.size)x\(entry.size).png"
        : "icon_\(entry.size)x\(entry.size)@2x.png"
    try renderPNG(px: px).write(to: iconsetURL.appendingPathComponent(name))
}
print("iconset written: \(iconsetURL.path)")
