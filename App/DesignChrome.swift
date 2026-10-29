import AppKit
import SwiftUI
import TwoFACore

/// 设计稿里的面板没有系统标题栏。清掉 sheet 自带的标题和底色，才能按稿子的圆角和边线来画。
struct SheetWindowClear: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { Self.apply(to: view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { Self.apply(to: nsView.window) }
    }

    private static func apply(to window: NSWindow?) {
        guard let window else { return }
        window.isOpaque = false
        window.backgroundColor = .clear
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
    }
}

/// 自绘红黄绿。主窗口隐藏了系统按钮，靠它关闭、最小化、缩放；面板里只接关闭。
/// 主窗口传 spacing 8，和系统按钮间距一致；面板按设计稿用 6。
struct TrafficLights: View {
    @Environment(\.controlActiveState) private var activeState
    @State private var hovering = false
    var spacing: CGFloat = 6
    var onClose: () -> Void = {}
    var onMinimize: (() -> Void)?
    var onZoom: (() -> Void)?

    var body: some View {
        HStack(spacing: spacing) {
            button(onClose, help: L10n.text(L10nKey.actionClose)) {
                light(0xFF5F56, 0xE0443E, "xmark")
            }
            button(onMinimize) { light(0xFFBD2E, 0xDEA123, "minus") }
            button(onZoom) { light(0x27C93F, 0x1AAB29, nil) }
        }
        .contentShape(Rectangle())
        // 悬停任意一颗都要三颗一起出图标，和系统标题栏一致。
        .onContinuousHover { phase in
            hovering = if case .active = phase { true } else { false }
        }
    }

    @ViewBuilder
    private func button(_ perform: (() -> Void)?, help: String? = nil, label: () -> some View) -> some View {
        if let perform {
            Button(action: perform, label: label)
                .buttonStyle(.plain)
                .modifier(TrafficLightHelp(text: help))
        } else {
            label()
        }
    }

    /// 失焦时变灰；鼠标放上来恢复颜色并画出叉、减号和全屏图标。symbol 为 nil 表示绿灯，画全屏的两个对角三角。
    private func light(_ fill: UInt32, _ stroke: UInt32, _ symbol: String?) -> some View {
        let colored = hovering || activeState != .inactive
        return Circle()
            .fill(colored ? Color(hex: fill) : Color.gray.opacity(0.3))
            .frame(width: 12, height: 12)
            .overlay {
                if hovering {
                    if let symbol {
                        Image(systemName: symbol)
                            .font(.system(size: 7, weight: .black))
                            .foregroundStyle(Color.black.opacity(0.6))
                    } else {
                        FullScreenGlyph()
                            .fill(Color.black.opacity(0.6))
                            .frame(width: 6, height: 6)
                    }
                }
            }
            .overlay(Circle().stroke((colored ? Color(hex: stroke) : Color.gray).opacity(0.4), lineWidth: 1))
    }
}

/// 系统绿灯的全屏图标：左上、右下两个直角三角，中间留一条斜缝。SF Symbols 里没有一模一样的。
private struct FullScreenGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let gap = rect.width * 0.14
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - gap, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - gap))
        path.closeSubpath()
        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + gap, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + gap))
        path.closeSubpath()
        return path
    }
}

/// 没有提示语就不挂 help，避免黄绿按钮悬停时冒出空提示。
private struct TrafficLightHelp: ViewModifier {
    var text: String?

    func body(content: Content) -> some View {
        if let text {
            content.help(text)
        } else {
            content
        }
    }
}

/// 表单里的错误。纯红字和周围的圆角字段不在一个体系里，所以做成浅底、细边、带图标的一条。
struct FormNotice: View {
    @Environment(\.palette) private var palette
    var text: String

    private var tint: Color { Color(hex: 0xE5484D) }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(tint)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(palette.text)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, 10)
        .padding(.trailing, 12)
        .padding(.vertical, 8)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: palette.controlRadius, style: .continuous))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(tint)
                .frame(width: 3)
                .padding(.vertical, 8)
                .padding(.leading, 1)
        }
        .overlay(
            RoundedRectangle(cornerRadius: palette.controlRadius, style: .continuous)
                .stroke(tint.opacity(0.22), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: palette.controlRadius, style: .continuous))
    }
}

struct PaperPanel<Content: View>: View {
    var width: CGFloat
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(width: width)
            // sheet 使用系统自带的材质和圆角，避免再叠一层自绘玻璃。
            .background(SheetWindowClear())
    }
}

struct DesignField: View {
    @Environment(\.palette) private var palette
    var title: String
    var placeholder: String
    @Binding var text: String
    var monospaced = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(palette.text)
            TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(palette.secondary.opacity(0.85)))
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: monospaced ? .monospaced : .default))
                .foregroundStyle(palette.text)
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(palette.surface, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(palette.border, lineWidth: 1)
                )
        }
    }
}

struct KindSegments: View {
    @Environment(\.palette) private var palette
    @Binding var kind: OTPKind

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.text(L10nKey.fieldKind))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(palette.text)
            HStack(spacing: 0) {
                segment(.totp, L10n.text(L10nKey.kindTotp))
                segment(.hotp, L10n.text(L10nKey.kindHotp))
                segment(.steam, L10n.text(L10nKey.kindSteam))
            }
            .padding(2)
            .background(palette.menuFooter, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(palette.border, lineWidth: 1)
            )
        }
    }

    private func segment(_ value: OTPKind, _ title: String) -> some View {
        let selected = kind == value
        return Button {
            kind = value
        } label: {
            Text(title)
                .font(.system(size: 12, weight: selected ? .medium : .regular))
                .foregroundStyle(selected ? palette.accent : palette.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .background(selected ? palette.surface : Color.clear, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(selected ? palette.border.opacity(0.6) : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

enum ThemeMenuSpace {
    /// 放得下拉的面板共用这个坐标空间，列表按字段按钮的位置摆，不跟系统菜单走。
    static let name = "themeMenu"
}

struct ThemeMenuAnchorKey: PreferenceKey {
    static var defaultValue: CGRect? = nil
    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        if let next = nextValue() { value = next }
    }
}

struct ThemeMenuOption: Identifiable {
    var title: String
    var selected: Bool
    var action: () -> Void
    var id: String { title }
}

/// 系统 Menu 的面板颜色和圆角不跟四套主题走，所以字段和列表都用 palette 自己画。
struct ThemeMenuField: View {
    @Environment(\.palette) private var palette
    var title: String
    var selection: String
    var isOpen: Bool
    /// 设置行左侧已有标题，字段本身不再画一行小字。
    var showsCaption = true
    var toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if showsCaption {
                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.secondary)
            }
            Button(action: toggle) {
                HStack(spacing: 6) {
                    Text(selection)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(palette.secondary)
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                }
                .font(.system(size: 12))
                .foregroundStyle(palette.text)
                .padding(.horizontal, 8)
                .frame(height: 28)
                .frame(maxWidth: .infinity)
                .background(palette.menuFooter, in: RoundedRectangle(cornerRadius: palette.controlRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: palette.controlRadius, style: .continuous)
                        .stroke(isOpen ? palette.accent : palette.border, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: ThemeMenuAnchorKey.self,
                    value: isOpen ? proxy.frame(in: .named(ThemeMenuSpace.name)) : nil
                )
            }
        }
    }
}

struct ThemeOptionList: View {
    @Environment(\.palette) private var palette
    var options: [ThemeMenuOption]
    var onPicked: () -> Void
    @State private var hovered: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(options) { option in
                Button {
                    option.action()
                    onPicked()
                } label: {
                    HStack(spacing: 6) {
                        Text(option.title)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        if option.selected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .semibold))
                        }
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(option.selected ? palette.accent : palette.text)
                    .padding(.horizontal, 8)
                    .frame(height: 28)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .background(rowFill(option))
                }
                .buttonStyle(.plain)
                .onHover { inside in
                    hovered = inside ? option.id : (hovered == option.id ? nil : hovered)
                }
            }
        }
        .padding(.vertical, 4)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: palette.controlRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: palette.controlRadius, style: .continuous)
                .stroke(palette.border, lineWidth: 1)
        )
        .shadow(color: palette.text.opacity(0.12), radius: 10, y: 4)
    }

    private func rowFill(_ option: ThemeMenuOption) -> Color {
        if option.selected { return palette.accent.opacity(0.12) }
        if hovered == option.id { return palette.menuFooter }
        return Color.clear
    }
}
