import SwiftUI

struct FloatingCountdownView: View {
  @ObservedObject var model: ReloModel
  let close: () -> Void

  @State private var isHovering = false
  @AppStorage(ReloSettingsKeys.timerPreset1) private var preset1 = TimerPresetConfiguration.defaultValues[0]
  @AppStorage(ReloSettingsKeys.timerPreset2) private var preset2 = TimerPresetConfiguration.defaultValues[1]
  @AppStorage(ReloSettingsKeys.timerPreset3) private var preset3 = TimerPresetConfiguration.defaultValues[2]

  var body: some View {
    ZStack(alignment: .topLeading) {
      RoundedRectangle(
        cornerRadius: ReloGeometry.floatingSurfaceRadius,
        style: .continuous
      )
        .fill(surfaceColor)
        .overlay {
          RoundedRectangle(
            cornerRadius: ReloGeometry.floatingSurfaceRadius,
            style: .continuous
          )
            .stroke(borderColor, lineWidth: 0.5)
        }

      countdownText
        .frame(maxWidth: .infinity, maxHeight: .infinity)

      Button(action: close) {
        Image(systemName: "xmark")
          .font(.system(size: 7, weight: .regular))
          .foregroundStyle(.gray)
          .frame(width: 16, height: 16)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .opacity(isHovering ? 1 : 0)
      .animation(.easeOut(duration: 0.12), value: isHovering)
      .padding(2)
      .accessibilityLabel("Hide floating countdown")
    }
    .frame(width: FloatingCountdownWindowController.contentSize.width,
           height: FloatingCountdownWindowController.contentSize.height)
    .contentShape(
      RoundedRectangle(
        cornerRadius: ReloGeometry.floatingSurfaceRadius,
        style: .continuous
      )
    )
    .onHover { isHovering = $0 }
    // The panel sets isMovableByWindowBackground, but the SwiftUI hosting view
    // consumes the mouse-down before AppKit's background drag can start, so the
    // window has to be dragged from inside SwiftUI. The close button keeps its
    // own clicks — a plain .gesture yields to controls.
    .modifier(WindowDrag())
  }

  /// The surface flips from black to white once the countdown has finished, so
  /// the window reads as "time's up" at a glance rather than looking like a
  /// paused timer. Digits and the hairline border invert with it.
  private var surfaceColor: Color {
    model.isFinished ? .white : .black
  }

  private var contentColor: Color {
    model.isFinished ? .black : .white
  }

  private var borderColor: Color {
    (model.isFinished ? Color.black : Color.white).opacity(0.10)
  }

  private var countdownText: some View {
    ViewThatFits(in: .horizontal) {
      countdownRow(fontSize: 29)
      countdownRow(fontSize: 25)
      countdownRow(fontSize: 21)
      countdownRow(fontSize: 18)
    }
    .padding(.horizontal, 8)
    .foregroundStyle(contentColor)
    .accessibilityLabel(displayText)
  }

  private func countdownRow(fontSize: CGFloat) -> some View {
    let components = displayText.split(separator: ":", omittingEmptySubsequences: false)
    return HStack(spacing: 0) {
      ForEach(Array(components.enumerated()), id: \.offset) { index, component in
        if index > 0 {
          CountdownColon(scale: fontSize / 29)
        }
        Text(String(component))
          .font(.system(size: fontSize, weight: .regular, design: .rounded).monospacedDigit())
      }
    }
    .fixedSize()
  }

  private var displayText: String {
    if model.isRunning {
      return model.formattedRemaining
    }
    let largestPreset = TimerPresetConfiguration.largestPresetValue(
      from: [preset1, preset2, preset3]
    )
    return TimerPresetConfiguration.statusDisplayText(forPresetValue: largestPreset)
  }
}

/// `WindowDragGesture` is macOS 15+. On macOS 14 the window stays put, the same
/// as before — AppKit's own background drag cannot reach past the hosting view.
private struct WindowDrag: ViewModifier {
  func body(content: Content) -> some View {
    if #available(macOS 15.0, *) {
      content.gesture(WindowDragGesture())
    } else {
      content
    }
  }
}

private struct CountdownColon: View {
  let scale: CGFloat

  var body: some View {
    VStack(spacing: 4 * scale) {
      Circle()
      Circle()
    }
    .frame(width: 5 * scale, height: 15 * scale)
    .padding(.horizontal, scale)
  }
}
