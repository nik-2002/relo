import SwiftUI

struct ReloMenuView: View {
  @EnvironmentObject private var model: ReloModel
  @Environment(\.menuDismiss) private var dismiss
  @State private var placeholder = Self.randomSuggestion()
  @FocusState private var isInputFocused: Bool
  @AppStorage(ReloSettingsKeys.defaultUnit) private var defaultUnit = DefaultTimeUnit.default.rawValue
  @AppStorage(ReloSettingsKeys.timerPreset1) private var preset1 = TimerPresetConfiguration.defaultValues[0]
  @AppStorage(ReloSettingsKeys.timerPreset2) private var preset2 = TimerPresetConfiguration.defaultValues[1]
  @AppStorage(ReloSettingsKeys.timerPreset3) private var preset3 = TimerPresetConfiguration.defaultValues[2]
  private let iconPointSize: CGFloat = 20
  private let buttonPointSize: CGFloat = 28

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
    VStack(alignment: .leading, spacing: 12) {
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
              if model.startFromInputs() {
                dismiss()
              }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .reloContentFill(cornerRadius: 6)
        .font(.system(size: 26, weight: .regular))
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
            if model.startPreset(preset.input) {
              dismiss()
            }
          } label: {
            Text(preset.displayName)
              .font(.system(size: 11, weight: .medium, design: .rounded))
              .lineLimit(1)
              .minimumScaleFactor(0.7)
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
          .help("Start a \(preset.input) timer")
          .accessibilityLabel("Start a \(preset.input) timer")
        }
      }
      .frame(maxWidth: .infinity)

      HStack(spacing: 2) {
        Button {
          SettingsPresentationCoordinator.present(
            dismissMenu: { dismiss() }
          )
        } label: {
          Image("settings")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: iconPointSize, height: iconPointSize)
            .frame(width: buttonPointSize, height: buttonPointSize)
            .foregroundStyle(.primary)
            .opacity(0.65)
        }
        .buttonStyle(HoverPillButtonStyle())

        Spacer()
        if model.canRepeat {
          Button {
            if model.repeatLastInput() {
              dismiss()
            }
          } label: {
            Image("repeat")
              .renderingMode(.template)
              .resizable()
              .scaledToFit()
              .frame(width: iconPointSize, height: iconPointSize)
              .frame(width: buttonPointSize, height: buttonPointSize)
              .foregroundStyle(.primary)
              .opacity(0.65)
          }
          .buttonStyle(HoverPillButtonStyle())
        }
        Button {
          if model.isRunning {
            if model.isPaused {
              if model.isFinished {
                model.startStopwatch()
                dismiss()
              } else {
                model.resume()
              }
            } else {
              model.pause()
            }
          } else {
            model.startStopwatch()
            dismiss()
          }
        } label: {
          Image((model.isRunning && !model.isPaused) ? "pause" : "play")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: iconPointSize, height: iconPointSize)
            .frame(width: buttonPointSize, height: buttonPointSize)
            .foregroundStyle(.primary)
            .opacity(0.65)
        }
        .buttonStyle(HoverPillButtonStyle())

        Button {
          model.stop()
          dismiss()
        } label: {
          Image("close")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: iconPointSize, height: iconPointSize)
            .frame(width: buttonPointSize, height: buttonPointSize)
            .foregroundStyle(.primary)
            .opacity(0.65)
        }
        .buttonStyle(HoverPillButtonStyle())
        .disabled(!model.isRunning)
        .opacity(model.isRunning ? 1 : 0.5)
      }
    }
    .padding(16)
    .frame(width: 210)
    .background(
      Color.clear
        .contentShape(Rectangle())
        .onTapGesture {
          isInputFocused = false
        }
    )
    .reloPanelSurface(cornerRadius: 18)
  }
}

private extension View {
  /// The primary floating "navigation layer" surface. Adopts Liquid Glass on
  /// macOS 26+ (adaptive tinting, system-drawn edge), falling back to the
  /// original frosted material + hairline stroke on macOS 14–25.
  @ViewBuilder
  func reloPanelSurface(cornerRadius: CGFloat) -> some View {
    let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    if #available(macOS 26.0, *) {
      self.glassEffect(.regular, in: shape)
    } else {
      self
        .background(.regularMaterial, in: shape)
        .overlay {
          shape.stroke(.separator.opacity(0.5), lineWidth: 0.5)
        }
        .clipShape(shape)
    }
  }

  /// A recessed *content* fill (the input field) that must NOT be glass, so it
  /// does not stack glass-on-glass over the panel. Uses a subtle hierarchical
  /// fill on macOS 26+, preserving the frosted material on macOS 14–25.
  @ViewBuilder
  func reloContentFill(cornerRadius: CGFloat) -> some View {
    let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    if #available(macOS 26.0, *) {
      self.background(shape.fill(.quaternary))
    } else {
      self.background(shape.fill(.regularMaterial))
    }
  }
}

private struct HoverPillButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    HoverPillButton(configuration: configuration)
  }

  private struct HoverPillButton: View {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme
    let configuration: ButtonStyle.Configuration
    @State private var isHovering = false

    var body: some View {
      configuration.label
        .padding(3)
        .background(
          RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(.regularMaterial)
            .opacity(backgroundOpacity)
        )
        .overlay(
          RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color.white.opacity(overlayOpacity))
        )
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .scaleEffect(configuration.isPressed ? 0.965 : 1)
        .onHover { hovering in
          isHovering = hovering
        }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var backgroundOpacity: Double {
      guard isEnabled else { return 0 }
      let targetOpacity: Double = colorScheme == .dark ? 0.95 : 0.55
      return (isHovering || configuration.isPressed) ? targetOpacity : 0
    }

    private var overlayOpacity: Double {
      guard isEnabled, colorScheme == .dark, (isHovering || configuration.isPressed) else { return 0 }
      return 0.04
    }

  }
}

#Preview {
  ReloMenuView()
    .environmentObject(ReloModel())
}
