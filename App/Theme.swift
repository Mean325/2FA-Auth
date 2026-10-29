import SwiftUI
import TwoFACore

enum ThemeID: String, Codable, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return L10n.text(L10nKey.settingsDarkModeSystem)
        case .light: return L10n.text(L10nKey.appearanceLight)
        case .dark: return L10n.text(L10nKey.appearanceDark)
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

struct ThemePalette {
    var background: Color
    /// 菜单栏浮层和主窗口共用主题，分别控制材质上的色调。
    var menuBackground: Color
    var menuFooter: Color
    var surface: Color
    var text: Color
    var secondary: Color
    var accent: Color
    var border: Color
    var radius: CGFloat
    var cardRadius: CGFloat
    var controlRadius: CGFloat
    var codeWeight: Font.Weight
    /// 深色模式的主按钮使用浅色强调色，搭配深色文字。
    var buttonForeground: Color
}

enum AppTheme {
    static let menuScale: CGFloat = 1.1
    static let menuWidth: CGFloat = 340 * menuScale
    static let menuListHeight: CGFloat = 360 * menuScale
    static let rowHeight: CGFloat = 64 * menuScale
    static let codeSize: CGFloat = 22
    static let horizontalPadding: CGFloat = 24
    static let windowWidth: CGFloat = 760
    static let windowHeight: CGFloat = 660

    static func resolved(_ id: ThemeID, colorScheme: ColorScheme) -> ThemeID {
        guard id == .system else { return id }
        return colorScheme == .dark ? .dark : .light
    }

    static func palette(_ id: ThemeID, colorScheme: ColorScheme) -> ThemePalette {
        if resolved(id, colorScheme: colorScheme) == .dark {
            return make(0x181B23, 0x20242E, 0x292E3B, 0x292E3B, 0xEFF2F8, 0xA2ABBC, 0xA4B6FF, 0x3B4252, 24, 18, 12, .medium, Color(hex: 0x181B23))
        }
        return make(0xF4F6FA, 0xF7F9FC, 0xEDF0F6, 0xFFFFFF, 0x202633, 0x737D8E, 0x5275E8, 0xE3E7EF, 24, 18, 12, .medium, .white)
    }

    private static func make(
        _ background: UInt32,
        _ menuBackground: UInt32,
        _ menuFooter: UInt32,
        _ surface: UInt32,
        _ text: UInt32,
        _ secondary: UInt32,
        _ accent: UInt32,
        _ border: UInt32,
        _ radius: CGFloat,
        _ cardRadius: CGFloat,
        _ controlRadius: CGFloat,
        _ weight: Font.Weight,
        _ buttonForeground: Color
    ) -> ThemePalette {
        ThemePalette(
            background: Color(hex: background),
            menuBackground: Color(hex: menuBackground),
            menuFooter: Color(hex: menuFooter),
            surface: Color(hex: surface),
            text: Color(hex: text),
            secondary: Color(hex: secondary),
            accent: Color(hex: accent),
            border: Color(hex: border),
            radius: radius,
            cardRadius: cardRadius,
            controlRadius: controlRadius,
            codeWeight: weight,
            buttonForeground: buttonForeground
        )
    }
}

extension Color {
    /// 主题色按设计说明的 sRGB 十六进制，不跟系统强调色走。
    init(hex: UInt32) {
        let red = Double((hex >> 16) & 0xff) / 255
        let green = Double((hex >> 8) & 0xff) / 255
        let blue = Double(hex & 0xff) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: 1)
    }
}

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = AppTheme.palette(.light, colorScheme: .light)
}

extension EnvironmentValues {
    var palette: ThemePalette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

struct AccentButton: View {
    @Environment(\.palette) private var palette
    var title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(palette.buttonForeground)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(palette.accent, in: RoundedRectangle(cornerRadius: palette.controlRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// 使用当前深浅色配色的确认层。
struct ConfirmDialog: View {
    @Environment(\.palette) private var palette
    var title: String
    var confirmTitle: String
    /// 删除时写上服务名和账号，避免只看到一句问话，不知道删的是哪一条。
    var name = ""
    var account = ""
    var destructive = false
    var onConfirm: () -> Void
    var onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)
            VStack(spacing: 16) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.text)
                    .multilineTextAlignment(.center)
                if !name.isEmpty {
                    VStack(spacing: 2) {
                        Text(name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(palette.text)
                            .lineLimit(1)
                        if !account.isEmpty, account != name {
                            Text(account)
                                .font(.system(size: 12))
                                .foregroundStyle(palette.secondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 10)
                    .background(palette.menuFooter, in: RoundedRectangle(cornerRadius: palette.controlRadius, style: .continuous))
                }
                HStack(spacing: 8) {
                    Button(action: onCancel) {
                        Text(L10n.text(L10nKey.actionCancel))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(palette.text)
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .background(palette.menuFooter, in: RoundedRectangle(cornerRadius: palette.controlRadius, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: palette.controlRadius, style: .continuous)
                                    .stroke(palette.border, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                    Button(action: onConfirm) {
                        Text(confirmTitle)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(destructive ? Color.white : palette.buttonForeground)
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .background(destructive ? Color(hex: 0xE5484D) : palette.accent, in: RoundedRectangle(cornerRadius: palette.controlRadius, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(24)
            .frame(width: 300)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: palette.radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: palette.radius, style: .continuous)
                    .stroke(palette.border, lineWidth: 1)
            )
            .shadow(color: palette.text.opacity(0.16), radius: 18, y: 8)
        }
    }
}

struct QuietButton: View {
    @Environment(\.palette) private var palette
    var title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(palette.secondary)
                .padding(.horizontal, 8)
                .frame(height: 28)
        }
        .buttonStyle(.plain)
    }
}

struct SearchField: View {
    enum Kind {
        case menu
        case window
    }

    @Environment(\.palette) private var palette
    @Binding var text: String
    var kind: Kind = .window
    var focused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: kind == .menu ? 12 : 13, weight: .medium))
                .foregroundStyle(palette.secondary)
            TextField(
                "",
                text: $text,
                prompt: Text(L10n.text(L10nKey.searchPlaceholder)).foregroundStyle(palette.secondary)
            )
            .focused(focused)
            .textFieldStyle(.plain)
            .font(.system(size: kind == .menu ? 13 : 12, weight: kind == .menu ? .medium : .regular))
            .foregroundStyle(palette.text)
            if kind == .menu {
                Text("⌘K")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(palette.secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(palette.menuFooter, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(palette.border, lineWidth: 1)
                    )
            }
        }
        .padding(.horizontal, 12)
        .frame(height: kind == .menu ? 28 * AppTheme.menuScale : 36)
        .background(palette.surface.opacity(0.55), in: RoundedRectangle(cornerRadius: palette.controlRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: palette.controlRadius, style: .continuous)
                .strokeBorder(focused.wrappedValue ? palette.accent.opacity(0.6) : palette.border.opacity(0.5), lineWidth: 0.5)
        )
    }
}
