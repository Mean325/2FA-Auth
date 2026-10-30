import SwiftUI
import TwoFACore

enum ExtensionEnvironment: String, CaseIterable, Identifiable {
    case development, test, sandbox, production

    var id: String { rawValue }
    var title: String {
        switch self {
        case .development: return L10n.text(L10nKey.environmentDevelopment)
        case .test: return L10n.text(L10nKey.environmentTest)
        case .sandbox: return L10n.text(L10nKey.environmentSandbox)
        case .production: return L10n.text(L10nKey.environmentProduction)
        }
    }
}

enum ExtensionProject: String, CaseIterable, Identifiable {
    case pyvio, actyve, cardbin, freeutx, rub, getShift

    var id: String { rawValue }
    var title: String {
        switch self {
        case .pyvio: return "Pyvio"
        case .actyve: return "Actyve"
        case .cardbin: return "Cardbin"
        case .freeutx: return "FreeUTX"
        case .rub: return "RUB"
        case .getShift: return "GetShift"
        }
    }
    var imageName: String { "Project-\(rawValue)" }
}

/// 对齐系统设置的拓展分段控件与列表：24 pt 控件、49 pt 行、26 pt 图标。
struct ExtensionSettingsPane: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("extensionActiveEnvironment") private var environment: ExtensionEnvironment = .development
    @State private var detailProject: ExtensionProject?

    private var groupBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.07) : Color(white: 0.965)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            environmentSegments
                .padding(.horizontal, 10)

            VStack(spacing: 0) {
                ForEach(ExtensionProject.allCases) { project in
                    projectRow(project)
                        .overlay(alignment: .bottom) {
                            if project != ExtensionProject.allCases.last {
                                Divider().opacity(0.55).padding(.horizontal, 10)
                            }
                        }
                }
            }
            .background(groupBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(.top, 10)
        .sheet(item: $detailProject) { project in
            ExtensionProjectSheet(project: project, environment: environment)
        }
    }

    private var environmentSegments: some View {
        HStack(spacing: 0) {
            ForEach(ExtensionEnvironment.allCases) { option in
                let selected = environment == option
                Button { environment = option } label: {
                    Text(option.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(selected ? .white : .primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 24)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color(nsColor: .controlAccentColor))
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .background(colorScheme == .dark ? Color.white.opacity(0.08) : Color(white: 0.925),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.text(L10nKey.settingsEnvironments))
    }

    private func projectRow(_ project: ExtensionProject) -> some View {
        HStack(spacing: 14) {
            ExtensionProjectIcon(project: project)
            VStack(alignment: .leading, spacing: 1) {
                Text(project.title)
                    .font(.system(size: 13))
                Text(L10n.text(L10nKey.settingsDeveloping))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Button { detailProject = project } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .offset(y: -5)
            .help(L10n.text(L10nKey.settingsProjectDetails))
            .accessibilityLabel(project.title + " · " + L10n.text(L10nKey.settingsProjectDetails))
        }
        .padding(.horizontal, 12)
        .frame(height: 49)
    }
}

private struct ExtensionProjectIcon: View {
    let project: ExtensionProject

    var body: some View {
        Image(project.imageName)
            .resizable()
            .scaledToFit()
            .frame(width: 24, height: 24)
            .frame(width: 26, height: 26)
            .background(.white, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .shadow(color: .black.opacity(0.14), radius: 1, y: 1)
            .accessibilityHidden(true)
    }
}

private struct ExtensionProjectSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    let project: ExtensionProject
    let environment: ExtensionEnvironment

    private var groupBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.07) : Color(white: 0.965)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 10) {
                    HStack(spacing: 12) {
                        ExtensionProjectIcon(project: project)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(String(format: L10n.text(L10nKey.settingsProjectDetailsTitle), project.title))
                                .font(.system(size: 13, weight: .bold))
                            Text(String(format: L10n.text(L10nKey.settingsCurrentEnvironment), environment.title))
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(groupBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    Text(L10n.text(L10nKey.settingsDeveloping))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                        .padding(.horizontal, 12)
                        .background(groupBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .padding(20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 0.5)
            HStack {
                Spacer(minLength: 0)
                Button(L10n.text(L10nKey.actionClose)) { dismiss() }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(minWidth: 64, minHeight: 24)
                    .background(Color(nsColor: .controlAccentColor), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .buttonStyle(.plain)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .frame(width: 470, height: 465)
        .background(colorScheme == .dark ? Color(nsColor: .windowBackgroundColor) : .white)
        .onExitCommand { dismiss() }
    }
}
