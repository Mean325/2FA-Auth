import AppKit
import SwiftUI
import TwoFACore

enum CodeFormat {
    static func grouped(_ raw: String, kind: OTPKind) -> String {
        if kind == .steam { return raw }
        let midpoint = raw.count == 8 ? 4 : 3
        guard raw.count > midpoint else { return raw }
        let index = raw.index(raw.startIndex, offsetBy: midpoint)
        return "\(raw[..<index]) \(raw[index...])"
    }

    /// 隐藏时仍占住验证码的宽度，解锁前后按钮位置不跳。
    static func masked(kind: OTPKind, digits: Int) -> String {
        let count = kind == .steam ? 5 : max(digits, 1)
        return grouped(String(repeating: "•", count: count), kind: kind)
    }

    static func styled(_ shown: String, size: CGFloat, weight: Font.Weight, tracking: CGFloat) -> AttributedString {
        var text = AttributedString(shown)
        text.font = .system(size: size, weight: weight, design: .monospaced)
        text.tracking = tracking
        if let separator = text.range(of: " ") {
            // 只将分隔空格的宽度和字距减半，数字本身保持原字号和字距。
            text[separator].font = .system(size: size / 2, weight: weight, design: .monospaced)
            text[separator].tracking = tracking / 2
        }
        return text
    }
}

struct CodeSnapshot {
    var raw: String
    var shown: String
    var expiring: Bool
    var showsCountdown: Bool
    var remaining: TimeInterval
    var period: TimeInterval
}

func codeSnapshot(record: VaultRecord, at time: TimeInterval, locked: Bool) -> CodeSnapshot {
    let remaining = OTPEngine.remaining(period: record.period, at: time)
    let moment = OTPEngine.displayTime(kind: record.kind, period: record.period, at: time)
    let raw = OTPEngine.code(
        secret: record.secret,
        kind: record.kind,
        algorithm: record.algorithm,
        digits: record.digits,
        period: record.period,
        counter: record.counter,
        at: moment
    )
    return CodeSnapshot(
        raw: raw,
        shown: locked ? CodeFormat.masked(kind: record.kind, digits: record.digits) : CodeFormat.grouped(raw, kind: record.kind),
        expiring: record.kind != .hotp && remaining <= 5,
        showsCountdown: record.kind != .hotp,
        remaining: remaining,
        period: TimeInterval(max(record.period, 1))
    )
}

enum AccountRowStyle {
    case menu
    /// 主窗口列表：一行一个账号
    case window
    /// 主窗口卡片：网格里一张一张
    case card
}

/// 主窗口的两种排法，存在 UserDefaults，下次打开保持上次的选择。
enum ListLayout: String {
    case list, cards
}

struct AccountRow: View {
    @Environment(\.palette) private var palette
    @Environment(AppSettings.self) private var settings
    var record: VaultRecord
    var now: TimeInterval
    var locked: Bool
    var style: AccountRowStyle
    var onUnlock: () -> Void
    var onNext: () -> Void
    @State private var failed = false
    @State private var hovering = false
    @State private var copied = false
    @State private var copyFeedbackTask: Task<Void, Never>?

    var body: some View {
        let snapshot = codeSnapshot(record: record, at: now, locked: locked)
        Group {
            switch style {
            case .menu: menuRow(snapshot)
            case .window: windowRow(snapshot)
            case .card: cardView(snapshot)
            }
        }
        .onDisappear {
            copyFeedbackTask?.cancel()
            copied = false
        }
    }

    /// 整张卡片用于复制，管理操作集中在设置。
    private func menuRow(_ snapshot: CodeSnapshot) -> some View {
        HStack(spacing: 10) {
            IssuerAvatar(title: record.displayTitle, size: 30)
            identity(snapshot, titleSize: 13, accountSize: 11)
            Spacer(minLength: 6)
            codeText(snapshot, size: 26, tracking: 1)
                .layoutPriority(1)
        }
        .padding(.horizontal, 14)
        .frame(height: AppTheme.rowHeight)
        .modifier(CodeCardSurface(hovering: hovering, copied: copied))
        .overlay(alignment: .bottom) { countdown(snapshot) }
        .clipShape(RoundedRectangle(cornerRadius: palette.cardRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: palette.cardRadius, style: .continuous))
        .onHover { hovering = $0 }
        .onTapGesture { copy() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { copy() }
        .help(L10n.text(L10nKey.listCopyHint))
    }

    private func windowRow(_ snapshot: CodeSnapshot) -> some View {
        HStack(spacing: 14) {
            IssuerAvatar(title: record.displayTitle, size: 38)
            identity(snapshot, titleSize: 14, accountSize: 12)
            Spacer(minLength: 12)
            codeText(snapshot, size: 30, tracking: 2)
            if snapshot.showsCountdown {
                secondsLabel(snapshot).frame(minWidth: 38, alignment: .trailing)
            } else {
                nextButton(size: 30)
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 82)
        .modifier(CodeCardSurface(hovering: hovering, copied: copied))
        .overlay(alignment: .bottom) { countdown(snapshot) }
        .clipShape(RoundedRectangle(cornerRadius: palette.cardRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: palette.cardRadius, style: .continuous))
        .onHover { hovering = $0 }
        .onTapGesture { copy() }
        .accessibilityAddTraits(.isButton)
    }

    private func cardView(_ snapshot: CodeSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                IssuerAvatar(title: record.displayTitle, size: 32)
                identity(snapshot, titleSize: 13, accountSize: 11)
                Spacer(minLength: 0)
            }
            Spacer(minLength: 18)
            HStack(alignment: .lastTextBaseline) {
                codeText(snapshot, size: 34, tracking: 2)
                Spacer(minLength: 8)
                if snapshot.showsCountdown {
                    secondsLabel(snapshot)
                } else {
                    nextButton(size: 24)
                }
            }
        }
        .padding(20)
        .frame(height: 156)
        .modifier(CodeCardSurface(hovering: hovering, copied: copied))
        .overlay(alignment: .bottom) { countdown(snapshot) }
        .clipShape(RoundedRectangle(cornerRadius: palette.cardRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: palette.cardRadius, style: .continuous))
        .onHover { hovering = $0 }
        .onTapGesture { copy() }
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private func countdown(_ snapshot: CodeSnapshot) -> some View {
        if snapshot.showsCountdown {
            CountdownBar(period: snapshot.period)
        }
    }

    private func codeText(_ snapshot: CodeSnapshot, size: CGFloat, tracking: CGFloat) -> some View {
        VStack(alignment: style == .card ? .leading : .trailing, spacing: 0) {
            Text(CodeFormat.styled(snapshot.shown, size: size, weight: palette.codeWeight, tracking: tracking))
                .foregroundStyle(snapshot.expiring ? CountdownColors.warning : palette.text)
                .lineLimit(1)
                .fixedSize()
            if copied {
                Label(L10n.text(L10nKey.copySuccess), systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(style == .menu ? palette.text : palette.accent)
                    .padding(.top, 3)
            } else if failed {
                copyFailed
            }
        }
    }

    private func secondsLabel(_ snapshot: CodeSnapshot) -> some View {
        Text(L10n.format(L10nKey.unitSeconds, Int(ceil(snapshot.remaining))))
            .font(.system(size: 12, weight: .medium).monospacedDigit())
            .foregroundStyle(snapshot.expiring ? CountdownColors.warning : palette.secondary)
    }

    private func nextButton(size: CGFloat) -> some View {
        Button(action: onNext) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(palette.secondary)
                .frame(width: size, height: size)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(L10n.text(L10nKey.hotpNext))
    }

    private func identity(_ snapshot: CodeSnapshot, titleSize: CGFloat, accountSize: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(record.account.isEmpty ? "—" : record.account)
                    .font(.system(size: titleSize, weight: style == .menu ? .bold : .semibold))
                    .tracking(titleSize >= 14 ? -0.2 : -0.13)
                    .foregroundStyle(palette.text)
                    .lineLimit(1)
                if record.kind == .hotp && style != .menu {
                    Text(L10n.text(L10nKey.hotpBadge))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(palette.text.opacity(0.04), in: RoundedRectangle(cornerRadius: 4))
                }

            }
            Text(record.issuer.isEmpty ? "—" : record.issuer)
                .font(.system(size: accountSize, weight: style == .menu ? .medium : .regular))
                .foregroundStyle(palette.secondary)
                .lineLimit(1)
        }
    }

    /// 复制失败贴在验证码下面，用和表单同一套提示色，但做成小胶囊，避免把整行撑开。
    private var copyFailed: some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 10))
            Text(L10n.text(L10nKey.copyFailed))
                .font(.system(size: 11))
        }
        .foregroundStyle(CountdownColors.warning)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(CountdownColors.warning.opacity(0.1), in: Capsule())
    }

    private func copy() {
        guard settings.twoFAEnabled else { return }
        if locked {
            onUnlock()
        } else if CodeClipboard.shared.copy(record: record) {
            failed = false
            copied = true
            copyFeedbackTask?.cancel()
            copyFeedbackTask = Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled else { return }
                copied = false
            }
        } else {
            copyFeedbackTask?.cancel()
            copied = false
            failed = true
        }
    }
}

enum CountdownColors {
    /// 最后 5 秒提醒用的颜色。使用柔和的红色，在深浅色背景上都保持清晰。
    static let warning = Color(hex: 0xE5484D)
}

/// 卡片底部的剩余时间横线，从右向左缩短。
struct CountdownBar: View {
    @Environment(\.palette) private var palette
    var period: TimeInterval
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // 直接按系统时间绘制，避免懒加载、滚动或复制反馈重建行时，各行补间动画不同步。
        TimelineView(.animation(minimumInterval: reduceMotion ? 1 : 1.0 / 30)) { timeline in
            let remaining = OTPEngine.remaining(period: Int(period), at: timeline.date.timeIntervalSince1970)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.accent.opacity(0.08))
                    Capsule()
                        .fill(remaining <= 5 ? CountdownColors.warning : palette.accent)
                        .frame(width: proxy.size.width * max(0, min(1, remaining / period)))
                }
            }
        }
        .frame(height: 2)
        .accessibilityHidden(true)
    }
}

/// 服务名首字做头像。底色取主题强调色的浅版，深浅色模式下都协调，不用每个服务配图标。
struct IssuerAvatar: View {
    @Environment(\.palette) private var palette
    var title: String
    var size: CGFloat

    var body: some View {
        Text(initial)
            .font(.system(size: size * 0.44, weight: .semibold))
            .foregroundStyle(palette.accent)
            .frame(width: size, height: size)
            .background(palette.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
    }

    private var initial: String {
        guard let first = title.trimmingCharacters(in: .whitespaces).first else { return "?" }
        return String(first).uppercased()
    }
}
