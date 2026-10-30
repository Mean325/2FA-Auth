import AppKit
import SwiftUI
import TwoFACore

// 窗口、搜索框和系统设置图标沿用 CodexLinxDisplay 的设置实现。
struct SettingsSearchField: NSViewRepresentable {
  @Binding var text: String
  var placeholder = L10n.text(L10nKey.settingsSearch)

  func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

  func makeNSView(context: Context) -> NSSearchField {
    let field = NSSearchField()
    field.placeholderString = placeholder
    field.controlSize = .large
    field.font = .systemFont(ofSize: 13)
    field.focusRingType = .default
    field.sendsSearchStringImmediately = true
    field.sendsWholeSearchString = false
    field.delegate = context.coordinator
    field.setAccessibilityLabel(placeholder)
    field.setContentHuggingPriority(.defaultLow, for: .horizontal)
    return field
  }

  func updateNSView(_ field: NSSearchField, context: Context) {
    field.placeholderString = placeholder
    field.setAccessibilityLabel(placeholder)
    context.coordinator.text = $text
    if field.stringValue != text { field.stringValue = text }
  }

  func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSSearchField, context: Context) -> CGSize? {
    CGSize(width: proposal.width ?? 212, height: 30)
  }

  final class Coordinator: NSObject, NSSearchFieldDelegate {
    var text: Binding<String>
    init(text: Binding<String>) { self.text = text }

    func controlTextDidChange(_ notification: Notification) {
      guard let field = notification.object as? NSSearchField else { return }
      text.wrappedValue = field.stringValue
    }
  }
}

struct SettingsWindowConfigurator: NSViewRepresentable {
  var title: String
  final class Coordinator {
    var configuredWindows = Set<ObjectIdentifier>()
  }

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  func makeNSView(context: Context) -> NSView {
    let view = NSView(frame: .zero)
    configureWhenAttached(view, coordinator: context.coordinator)
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    configureWhenAttached(nsView, coordinator: context.coordinator)
  }

  private func configureWhenAttached(_ view: NSView, coordinator: Coordinator) {
    DispatchQueue.main.async {
      guard let window = view.window else { return }

      window.title = title
      window.identifier = NSUserInterfaceItemIdentifier("keymark-settings")
      window.titleVisibility = .visible
      window.titlebarAppearsTransparent = true
      window.titlebarSeparatorStyle = .none
      window.toolbarStyle = .unified
      window.styleMask.insert(.fullSizeContentView)
      window.styleMask.insert(.resizable)
      window.styleMask.insert(.titled)
      window.hasShadow = true
      window.isMovableByWindowBackground = true
      window.minSize = NSSize(width: 720, height: 600)
      window.isOpaque = false
      window.backgroundColor = .clear

      window.standardWindowButton(.closeButton)?.isHidden = false
      window.standardWindowButton(.miniaturizeButton)?.isHidden = false
      window.standardWindowButton(.zoomButton)?.isHidden = false

      let identifier = ObjectIdentifier(window)
      if coordinator.configuredWindows.insert(identifier).inserted {
        // Let the window receive initial keyboard focus; search remains
        // available when explicitly clicked or reached with Tab.
        window.initialFirstResponder = window.contentView
        window.makeFirstResponder(nil)
        window.setContentSize(NSSize(width: 760, height: 660))
        window.center()
      }
    }
  }
}


struct SettingsSystemIcon: View {
  enum Kind: String, CaseIterable {
    case general, monitoring, keyboard, display, appearance, network, login, update, about, sync, messages, mail, extensions

    var path: String {
      let root = "/System/Library/ExtensionKit/Extensions/"
      switch self {
      case .general: return "/System/Applications/System Settings.app/Contents/PlugIns/GeneralSettings.appex"
      case .monitoring: return root + "ControlCenterSettings.appex"
      case .keyboard: return root + "KeyboardSettings.appex"
      case .display: return root + "DisplaysExt.appex"
      case .appearance: return root + "Appearance.appex"
      case .network: return root + "Network.appex"
      case .login: return root + "LoginItems.appex"
      case .update: return root + "SoftwareUpdateSettingsExtension.appex"
      case .about: return root + "AboutExtension.appex"
      case .sync: return root + "DateAndTime Extension.appex"
      case .messages: return "/System/Applications/Messages.app"
      case .mail: return "/System/Applications/Mail.app"
      case .extensions: return root + "AppExtensionManagement.appex"
      }
    }

    var fallback: String {
      switch self {
      case .general: return "gear"
      case .monitoring: return "switch.2"
      case .keyboard: return "keyboard"
      case .display: return "sun.max.fill"
      case .appearance: return "circle.lefthalf.filled"
      case .network: return "network"
      case .login: return "list.bullet"
      case .update: return "gear.badge"
      case .about: return "laptopcomputer"
      case .sync: return "clock"
      case .messages: return "message.fill"
      case .mail: return "envelope.fill"
      case .extensions: return "puzzlepiece.extension.fill"
      }
    }

    static func forSymbol(_ symbol: String) -> Kind {
      switch symbol {
      case "keyboard", "keyboard.badge.ellipsis": return .keyboard
      case "rectangle.2.swap", "slider.horizontal.3": return .display
      case "paintpalette", "rectangle.3.group": return .appearance
      case "network", "checkmark.circle.fill", "exclamationmark.triangle.fill": return .network
      case "power": return .login
      case "arrow.triangle.2.circlepath": return .update
      case "info.circle": return .about
      case "clock.arrow.trianglehead.counterclockwise.rotate.90": return .sync
      default: return .monitoring
      }
    }
  }

  let kind: Kind
  let size: CGFloat

  private static let images: [Kind: NSImage] = Dictionary(uniqueKeysWithValues:
    Kind.allCases.compactMap { kind in
      guard FileManager.default.fileExists(atPath: kind.path) else { return nil }
      return (kind, NSWorkspace.shared.icon(forFile: kind.path))
    })

  var body: some View {
    if let image = Self.images[kind] {
      Image(nsImage: image)
        .resizable()
        .interpolation(.high)
        .frame(width: size * 1.18, height: size * 1.18)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    } else {
      Image(systemName: kind.fallback)
        .font(.system(size: size * 0.65))
        .foregroundStyle(.white)
        .frame(width: size, height: size)
        .background(Color.gray.gradient, in: RoundedRectangle(cornerRadius: size * 0.24))
        .accessibilityHidden(true)
    }
  }
}


struct SettingsGlassButton: ViewModifier {
  var prominent = false
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

  @ViewBuilder
  func body(content: Content) -> some View {
    if #available(macOS 26.0, *), !reduceTransparency {
      if prominent { content.buttonStyle(.glassProminent) }
      else { content.buttonStyle(.glass) }
    } else {
      if prominent { content.buttonStyle(.borderedProminent) }
      else { content.buttonStyle(.bordered) }
    }
  }
}

