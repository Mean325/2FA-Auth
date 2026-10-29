import AppKit
import SwiftUI

/// 玻璃用于浮层和导航；内容卡片使用轻量表面，避免玻璃层层叠加。
struct GlassSurface: ViewModifier {
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var cornerRadius: CGFloat
    var interactive = false

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if reduceTransparency {
            content.background(palette.background, in: shape)
                .overlay(shape.strokeBorder(palette.border.opacity(0.6), lineWidth: 0.5))
        } else if #available(macOS 26.0, *) {
            content.glassEffect(
                .regular.tint(palette.background.opacity(0.18)).interactive(interactive),
                in: shape
            )
        } else {
            content.background(.ultraThinMaterial, in: shape)
                .background(palette.background.opacity(0.35), in: shape)
                .overlay(shape.strokeBorder(palette.border.opacity(0.6), lineWidth: 0.5))
        }
    }
}

struct CodeCardSurface: ViewModifier {
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var hovering = false
    var copied = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: palette.cardRadius, style: .continuous)
        content
            .background(copied ? palette.accent.opacity(0.14) : palette.surface.opacity(reduceTransparency ? 1 : hovering ? 0.92 : 0.68), in: shape)
            .overlay(shape.strokeBorder(copied ? palette.accent.opacity(0.7) : hovering ? palette.accent.opacity(0.25) : palette.border.opacity(0.45), lineWidth: copied ? 1.2 : 0.5))
            .shadow(color: palette.text.opacity(hovering ? 0.045 : 0.02), radius: 10, y: 3)
    }
}

