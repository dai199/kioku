import AppKit

/// Kiokuのブランドアイコン（吹き出し＋K）をコードで描画する。
/// メニューバー用はテンプレート画像（モノクロ、色反転はOSに任せる。HIG: The menu bar）。
/// アプリアイコン（Assets/Kioku.icns）と同じモチーフ。
@MainActor
enum BrandIcon {
    /// メニューバー・フローティングアイコン用テンプレート画像。
    /// 塗りつぶした吹き出しから「K」を抜いたシルエット。
    static let template: NSImage = makeTemplate(badged: false)

    /// 未読があるときのメニューバー用。右上にドットを足す。
    /// 色はOSに任せる原則を守るため、赤ではなくテンプレートのまま
    /// 「透明な隙間で切り離したドット」として描く（DESIGN.md）。
    static let templateWithBadge: NSImage = makeTemplate(badged: true)

    private static func makeTemplate(badged: Bool) -> NSImage {
        let size: CGFloat = 18
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            // 吹き出し本体＋左下のしっぽ
            let bubble = NSBezierPath(
                roundedRect: NSRect(x: 1, y: 4, width: 16, height: 13),
                xRadius: 4.5, yRadius: 4.5
            )
            let tail = NSBezierPath()
            tail.move(to: NSPoint(x: 4.5, y: 5))
            tail.line(to: NSPoint(x: 3.5, y: 0.5))
            tail.line(to: NSPoint(x: 8.5, y: 4.5))
            tail.close()
            NSColor.black.setFill()
            bubble.fill()
            tail.fill()

            // 「K」を抜く（destinationOutで透明に）
            let text = NSAttributedString(string: "K", attributes: [
                .font: NSFont.systemFont(ofSize: 10, weight: .heavy),
                .foregroundColor: NSColor.black,
            ])
            let textSize = text.size()
            let context = NSGraphicsContext.current
            context?.compositingOperation = .destinationOut
            text.draw(at: NSPoint(
                x: 1 + (16 - textSize.width) / 2,
                y: 4 + (13 - textSize.height) / 2
            ))
            context?.compositingOperation = .sourceOver

            if badged {
                let center = NSPoint(x: 14.5, y: 14.5)
                let radius: CGFloat = 3
                let gap: CGFloat = 1.2
                // 吹き出しから切り離すため、ドットの周りを一度くり抜く
                context?.compositingOperation = .destinationOut
                NSBezierPath(ovalIn: NSRect(
                    x: center.x - radius - gap, y: center.y - radius - gap,
                    width: (radius + gap) * 2, height: (radius + gap) * 2
                )).fill()
                context?.compositingOperation = .sourceOver
                NSBezierPath(ovalIn: NSRect(
                    x: center.x - radius, y: center.y - radius,
                    width: radius * 2, height: radius * 2
                )).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
