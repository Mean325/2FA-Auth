import AppKit

/// 钥记的品牌标志：倒计时环包住一个钥匙孔，意思是「会过期的口令」。
/// 应用图标、状态栏、窗口左上角共用这一份绘制代码；scripts/IconExport 也直接编译本文件导出 PNG，改造型只改这里。
enum IconMark {
    static let blueTop = NSColor(srgbRed: 0.278, green: 0.553, blue: 0.984, alpha: 1)
    static let blueBottom = NSColor(srgbRed: 0.129, green: 0.333, blue: 0.851, alpha: 1)

    /// 状态栏模板图：只用黑色和透明度，系统会按菜单栏明暗自动反色。
    static func menuBarImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            drawGlyph(
                in: rect.insetBy(dx: 1.5, dy: 1.5),
                ink: .black,
                track: NSColor.black.withAlphaComponent(0.3),
                ringWidth: 0.14
            )
            return true
        }
        image.isTemplate = true
        return image
    }

    /// 矢量版应用图标，按显示尺寸实时绘制，窗口里用不会糊。底色固定为品牌蓝，给 Dock 导出和菜单栏小窗用。
    static func appIcon(side: CGFloat) -> NSImage {
        appIcon(side: side, top: blueTop, bottom: blueBottom)
    }

    /// 窗口头部用。底色跟当前主题的强调色走，钥匙孔和倒计时环仍是白色，造型和 Dock 图标一致。
    static func appIcon(side: CGFloat, accent: NSColor) -> NSImage {
        let top = accent.blended(withFraction: 0.22, of: .white) ?? accent
        return appIcon(side: side, top: top, bottom: accent)
    }

    private static func appIcon(side: CGFloat, top: NSColor, bottom: NSColor) -> NSImage {
        NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            drawAppIcon(in: rect, top: top, bottom: bottom)
            return true
        }
    }

    static func drawAppIcon(in canvas: NSRect) {
        drawAppIcon(in: canvas, top: blueTop, bottom: blueBottom)
    }

    /// 按 macOS 图标网格绘制：1024 画布里放 824 的圆角方块，四周留出阴影位置，
    /// 不留边的话 Dock 里会比系统图标大一圈，看起来很突兀。
    static func drawAppIcon(in canvas: NSRect, top: NSColor, bottom: NSColor) {
        let side = canvas.width
        let tile = canvas.insetBy(dx: side * 100 / 1024, dy: side * 100 / 1024)
        let radius = tile.width * 0.2237
        let shape = NSBezierPath(roundedRect: tile, xRadius: radius, yRadius: radius)

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
        shadow.shadowBlurRadius = side * 0.03
        shadow.shadowOffset = NSSize(width: 0, height: -side * 0.012)
        shadow.set()
        bottom.setFill()
        shape.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.saveGraphicsState()
        shape.addClip()
        NSGradient(starting: top, ending: bottom)?.draw(in: tile, angle: -90)
        // 上半部一层很淡的高光，让底色有体积感
        NSGradient(colors: [NSColor.white.withAlphaComponent(0.16), NSColor.white.withAlphaComponent(0)])?
            .draw(in: NSRect(x: tile.minX, y: tile.midY, width: tile.width, height: tile.height / 2), angle: -90)
        NSGraphicsContext.restoreGraphicsState()

        drawGlyph(
            in: tile.insetBy(dx: tile.width * 0.21, dy: tile.width * 0.21),
            ink: .white,
            track: NSColor.white.withAlphaComponent(0.28),
            ringWidth: 0.11
        )
    }

    /// 环从 12 点顺时针走 3/4，留下的缺口代表倒计时剩余；中间是实心钥匙孔。
    static func drawGlyph(in rect: NSRect, ink: NSColor, track: NSColor, ringWidth: CGFloat) {
        let size = min(rect.width, rect.height)
        let line = size * ringWidth
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let radius = size / 2 - line / 2

        let trackPath = NSBezierPath()
        trackPath.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
        trackPath.lineWidth = line
        track.setStroke()
        trackPath.stroke()

        let arc = NSBezierPath()
        arc.appendArc(withCenter: center, radius: radius, startAngle: 90, endAngle: -180, clockwise: true)
        arc.lineWidth = line
        arc.lineCapStyle = .round
        ink.setStroke()
        arc.stroke()

        ink.setFill()
        let hole = size * 0.13
        let holeCenter = NSPoint(x: center.x, y: center.y + size * 0.07)
        NSBezierPath(ovalIn: NSRect(x: holeCenter.x - hole, y: holeCenter.y - hole, width: hole * 2, height: hole * 2)).fill()
        let topHalf = hole * 0.5
        let bottomHalf = hole * 0.8
        let bottomY = center.y - size * 0.2
        let stem = NSBezierPath()
        stem.move(to: NSPoint(x: center.x - topHalf, y: holeCenter.y))
        stem.line(to: NSPoint(x: center.x + topHalf, y: holeCenter.y))
        stem.line(to: NSPoint(x: center.x + bottomHalf, y: bottomY))
        stem.line(to: NSPoint(x: center.x - bottomHalf, y: bottomY))
        stem.close()
        stem.fill()
    }
}
