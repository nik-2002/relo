import SwiftUI

struct ReloMenuView: View {
  let usesSystemPopoverSurface: Bool
  @EnvironmentObject private var model: ReloModel
  @Environment(\.menuDismiss) private var dismiss
  @Environment(\.menuSecondaryToggle) private var toggleSecondaryMenu
  @State private var placeholder = Self.randomSuggestion()
  @FocusState private var isInputFocused: Bool
  @AppStorage(ReloSettingsKeys.defaultUnit) private var defaultUnit = DefaultTimeUnit.default.rawValue
  @AppStorage(ReloSettingsKeys.timerPreset1) private var preset1 = TimerPresetConfiguration.defaultValues[0]
  @AppStorage(ReloSettingsKeys.timerPreset2) private var preset2 = TimerPresetConfiguration.defaultValues[1]
  @AppStorage(ReloSettingsKeys.timerPreset3) private var preset3 = TimerPresetConfiguration.defaultValues[2]

  private static let primaryCardWidth: CGFloat = 242

  init(usesSystemPopoverSurface: Bool = false) {
    self.usesSystemPopoverSurface = usesSystemPopoverSurface
  }

  private var timerPresets: [TimerPreset] {
    let unit = DefaultTimeUnit(rawValue: defaultUnit) ?? .default
    let values = TimerPresetConfiguration.resolvedValues(
      from: [preset1, preset2, preset3]
    )
    return TimerPresetConfiguration.uniquePresets(
      from: values,
      defaultUnit: unit
    )
  }

  private var defaultPresetInput: String {
    TimerPresetConfiguration.largestPresetValue(
      from: [preset1, preset2, preset3]
    )
  }

  private static let suggestions = [
    "10s", "30 sec", "45 secs",
    "1 min", "5 mins", "12 minutes",
    "20m", "25 min", "45 minutes",
    "1h", "1 hr", "1.5 hrs", "2 hours",
    "3h", "4 hours", "17m 45s", "1h 30m",
    "25:00", "10pm", "6:15a", "noon",
  ]

  private static func randomSuggestion() -> String {
    suggestions.randomElement() ?? "10s"
  }

  var body: some View {
    if usesSystemPopoverSurface {
      primaryCard
    } else {
      primaryCard.reloMenuSurface()
    }
  }

  private var primaryCard: some View {
    VStack(alignment: .leading, spacing: 8) {
      VStack(alignment: .leading, spacing: 5) {
        ZStack(alignment: .leading) {
          if model.inputDuration.isEmpty {
            Text(placeholder)
              .foregroundColor(.secondary.opacity(0.35))
          }

          TextField("", text: $model.inputDuration)
            .focused($isInputFocused)
            .textFieldStyle(.plain)
            .onChange(of: model.inputDuration) { _, _ in
              model.inputErrorMessage = nil
            }
            .onSubmit {
              _ = model.startFromInputs(defaultingTo: defaultPresetInput)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .reloNestedContentFill()
        .font(.system(size: 19.5, weight: .regular))
        .frame(maxWidth: .infinity, alignment: .leading)

        if let inputErrorMessage = model.inputErrorMessage {
          Text(inputErrorMessage)
            .font(.caption)
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 2)
        }
      }

      .onAppear {
        placeholder = Self.randomSuggestion()
        DispatchQueue.main.async {
          isInputFocused = true
        }
      }
      .onReceive(
        NotificationCenter.default.publisher(for: Notification.Name("ReloPopoverWillShow"))
      ) { _ in
        placeholder = Self.randomSuggestion()
        DispatchQueue.main.async {
          isInputFocused = true
        }
      }

      HStack(spacing: 5) {
        ForEach(timerPresets) { preset in
          Button {
            _ = model.startPreset(preset.input)
          } label: {
            Text(preset.displayName)
              .font(.system(size: 12, weight: .medium, design: .rounded))
              .lineLimit(1)
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
          .fixedSize(horizontal: true, vertical: false)
          .help("Start a \(preset.input) timer")
          .accessibilityLabel("Start a \(preset.input) timer")
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      HStack(spacing: 2) {
        actionControls

        Spacer(minLength: 2)

        Button {
          isInputFocused = false
          toggleSecondaryMenu()
        } label: {
          Image(systemName: "ellipsis")
            .font(.system(size: 14, weight: .regular))
            .frame(width: 22, height: 22)
            .foregroundStyle(.secondary)
        }
        .buttonStyle(MenuTextButtonStyle())
        .help("More options")
        .accessibilityLabel("Show more options")
      }
      .animation(
        .snappy(duration: 0.26, extraBounce: 0),
        value: model.isRunning
      )
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .frame(width: Self.primaryCardWidth)
    .background(
      Color.clear
        .contentShape(Rectangle())
        .onTapGesture {
          isInputFocused = false
        }
    )
  }

}

struct ReloSecondaryMenuView: View {
  let usesSystemPopoverSurface: Bool
  let setFloatingDisplayEnabled: (Bool) -> Void
  @Environment(\.menuDismiss) private var dismiss
  @AppStorage(ReloSettingsKeys.floatingCountdownDisplayEnabled) private var floatingDisplayEnabled = false

  init(
    usesSystemPopoverSurface: Bool = false,
    setFloatingDisplayEnabled: @escaping (Bool) -> Void = { enabled in
      UserDefaults.standard.set(
        enabled,
        forKey: ReloSettingsKeys.floatingCountdownDisplayEnabled
      )
    }
  ) {
    self.usesSystemPopoverSurface = usesSystemPopoverSurface
    self.setFloatingDisplayEnabled = setFloatingDisplayEnabled
  }

  var body: some View {
    if usesSystemPopoverSurface {
      secondaryCard
    } else {
      secondaryCard.reloMenuSurface()
    }
  }

  private var secondaryCard: some View {
    VStack(spacing: 0) {
      secondaryMenuButton("Settings...") {
        SettingsPresentationCoordinator.present(
          dismissMenu: { dismiss() }
        )
      }

      Divider()

      secondaryMenuButton(
        floatingDisplayEnabled ? "Hide Floating Display" : "Show Floating Display"
      ) {
        setFloatingDisplayEnabled(!floatingDisplayEnabled)
      }

      Divider()

      secondaryMenuButton("About Relo") {
        showAboutPanel()
        dismiss()
      }

      secondaryMenuButton("Quit") {
        NSApp.terminate(nil)
      }
    }
    .padding(4)
    .frame(
      width: SecondaryMenuPanel.contentSize.width,
      height: SecondaryMenuPanel.contentSize.height
    )
  }

  private func secondaryMenuButton(
    _ title: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Text(title)
        .font(.system(size: 12, weight: .medium, design: .rounded))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .frame(height: 30)
        .contentShape(Rectangle())
    }
    .buttonStyle(SecondaryMenuButtonStyle())
  }

  private func showAboutPanel() {
    let icon = Bundle.main.url(forResource: "AppIcon", withExtension: "icns")
      .flatMap(NSImage.init(contentsOf:)) ?? NSApp.applicationIconImage ?? NSImage()
    NSApp.activate(ignoringOtherApps: true)
    NSApp.orderFrontStandardAboutPanel(options: [
      .applicationIcon: icon,
    ])
  }
}

extension ReloMenuView {

  private func menuTextButton(
    _ title: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Text(title)
        .font(.system(size: 12, weight: .medium, design: .rounded))
        .lineLimit(1)
    }
    .buttonStyle(MenuTextButtonStyle())
  }

  @ViewBuilder
  private var actionControls: some View {
    if model.isRunning {
      HStack(spacing: 2) {
        if !model.isFinished {
          fixedWidthPauseResumeButton {
            if model.isPaused {
              model.resume()
            } else {
              model.pause()
            }
          }
        }

        menuTextButton(Self.stopActionTitle(isFinished: model.isFinished)) {
          model.stop()
        }

        if case .countdown = model.mode {
          menuTextButton("restart") {
            _ = model.repeatLastInput()
          }
        }
      }
      .fixedSize(horizontal: true, vertical: false)
      .transition(actionControlsTransition)
    } else {
      menuTextButton("start") {
        _ = model.startFromInputs(defaultingTo: defaultPresetInput)
      }
      .transition(actionControlsTransition)
    }
  }

  private func fixedWidthPauseResumeButton(
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      ZStack {
        Text("resume")
          .hidden()
        Text(model.isPaused ? "resume" : "pause")
          .contentTransition(.opacity)
      }
      .font(.system(size: 12, weight: .medium, design: .rounded))
      .lineLimit(1)
      .animation(.easeInOut(duration: 0.16), value: model.isPaused)
    }
    .buttonStyle(MenuTextButtonStyle())
  }

  static func stopActionTitle(isFinished: Bool) -> String {
    isFinished ? "stop" : "cancel"
  }

  private var actionControlsTransition: AnyTransition {
    .opacity.combined(
      with: .scale(scale: 0.86, anchor: .leading)
    )
  }
}

private extension View {
  /// The primary floating "navigation layer" surface: frosted material with a
  /// hairline stroke. Deliberately does NOT use `.glassEffect` — this panel is
  /// a bespoke borderless, non-activating NSPanel at `.popUpMenu` level with a
  /// fully transparent background, not a standard system-composited window.
  /// Liquid Glass has no real backdrop to sample there, so instead of its
  /// usual soft translucent edge it falls back to a hard, opaque black rim.
  /// Wrapping it in `GlassEffectContainer` (the API's documented fix for edge
  /// compositing) did not change this, confirming it's structural rather than
  /// a missing-container issue.
  func reloMenuSurface() -> some View {
    let shape = RoundedRectangle(
      cornerRadius: ReloGeometry.menuSurfaceRadius,
      style: .continuous
    )
    return self
      .containerShape(shape)
      .background(.thinMaterial, in: shape)
      .overlay {
        shape.stroke(.separator.opacity(0.35), lineWidth: 0.5)
      }
      .clipShape(shape)
  }

  /// A recessed *content* fill (the input field) that must NOT be glass, so it
  /// does not stack glass-on-glass over the panel. Uses a subtle hierarchical
  /// fill on macOS 26+, preserving the frosted material on macOS 14–25.
  @ViewBuilder
  func reloNestedContentFill() -> some View {
    if #available(macOS 26.0, *) {
      self.background(
        ConcentricRectangle(
          corners: .concentric(
            minimum: .fixed(ReloGeometry.compactControlRadius)
          ),
          isUniform: true
        )
        .fill(.quaternary)
      )
    } else {
      let shape = RoundedRectangle(
        cornerRadius: ReloGeometry.compactControlRadius,
        style: .continuous
      )
      self.background(shape.fill(.regularMaterial))
    }
  }
}

private struct SecondaryMenuButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    SecondaryMenuButton(configuration: configuration)
  }

  private struct SecondaryMenuButton: View {
    @State private var isHovering = false
    let configuration: ButtonStyle.Configuration

    var body: some View {
      configuration.label
        .foregroundStyle(isHovering ? Color(nsColor: .windowBackgroundColor) : .primary)
        .background {
          RoundedRectangle(
            cornerRadius: ReloGeometry.compactControlRadius,
            style: .continuous
          )
            .fill(Color.primary.opacity(isHovering ? 0.82 : 0))
            .padding(.horizontal, 5)
            .padding(.vertical, 4)
            .allowsHitTesting(false)
        }
        .opacity(configuration.isPressed ? 0.70 : 1)
        .onHover { hovering in
          isHovering = hovering
        }
        .animation(.easeOut(duration: 0.10), value: isHovering)
    }
  }
}

private struct MenuTextButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    MenuTextButton(configuration: configuration)
  }

  private struct MenuTextButton: View {
    @Environment(\.isEnabled) private var isEnabled
    let configuration: ButtonStyle.Configuration

    var body: some View {
      configuration.label
        .padding(.horizontal, 5)
        .padding(.vertical, 4)
        .contentShape(
          RoundedRectangle(
            cornerRadius: ReloGeometry.compactControlRadius,
            style: .continuous
          )
        )
        .opacity(isEnabled ? (configuration.isPressed ? 0.62 : 1) : 0.38)
    }

  }
}

#Preview {
  ReloMenuView()
    .environmentObject(ReloModel())
}
