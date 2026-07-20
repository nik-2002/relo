import SwiftUI

struct TimerPresetSettingsSection: View {
  @AppStorage(ReloSettingsKeys.timerPreset1) private var preset1 = TimerPresetConfiguration.defaultValues[0]
  @AppStorage(ReloSettingsKeys.timerPreset2) private var preset2 = TimerPresetConfiguration.defaultValues[1]
  @AppStorage(ReloSettingsKeys.timerPreset3) private var preset3 = TimerPresetConfiguration.defaultValues[2]
  @State private var errorMessage: String?
  private let minutesFormatter = PresetMinutesFormatter()

  var body: some View {
    Section("Timer Presets (min)") {
      VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 8) {
          presetInput(index: 0, value: preset1)
          presetInput(index: 1, value: preset2)
          presetInput(index: 2, value: preset3)
        }

        if let errorMessage {
          Text(errorMessage)
            .font(.caption)
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
    .onAppear {
      setValues(TimerPresetConfiguration.resolvedValues(from: values))
    }
  }

  private func presetInput(index: Int, value: String) -> some View {
    HStack(spacing: 2) {
      TextField(
        "Preset \(index + 1)",
        value: minuteBinding(at: index),
        formatter: minutesFormatter
      )
      .labelsHidden()
      .textFieldStyle(.plain)
      .multilineTextAlignment(.center)
      .monospacedDigit()
      .frame(maxWidth: .infinity)

      Stepper(
        "Preset \(index + 1)",
        onIncrement: { adjustPreset(at: index, direction: 1) },
        onDecrement: { adjustPreset(at: index, direction: -1) }
      )
      .labelsHidden()
      .controlSize(.small)
      .accessibilityValue(displayName(for: value))
    }
    .padding(.leading, 8)
    .padding(.trailing, 4)
    .frame(maxWidth: .infinity, minHeight: 30)
    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
  }

  private func minuteBinding(at index: Int) -> Binding<Int> {
    Binding(
      get: {
        guard values.indices.contains(index) else {
          return TimerPresetConfiguration.minuteRange.lowerBound
        }
        return TimerPresetConfiguration.minutes(from: values[index])
          ?? TimerPresetConfiguration.minuteRange.lowerBound
      },
      set: { updatePreset(at: index, minutes: $0) }
    )
  }

  private var values: [String] {
    [preset1, preset2, preset3]
  }

  private func adjustPreset(at index: Int, direction: Int) {
    let resolvedValues = TimerPresetConfiguration.resolvedValues(from: values)
    guard resolvedValues.indices.contains(index),
          let currentMinutes = TimerPresetConfiguration.minutes(from: resolvedValues[index]) else {
      return
    }
    updatePreset(
      at: index,
      minutes: TimerPresetConfiguration.steppedMinutes(
        from: currentMinutes,
        direction: direction
      )
    )
  }

  private func updatePreset(at index: Int, minutes: Int) {
    var nextValues = TimerPresetConfiguration.resolvedValues(from: values)
    guard nextValues.indices.contains(index) else { return }

    let clampedMinutes = TimerPresetConfiguration.clampedMinutes(minutes)
    let otherMinutes = Set(nextValues.enumerated().compactMap { slot, value in
      slot == index ? nil : TimerPresetConfiguration.minutes(from: value)
    })
    guard !otherMinutes.contains(clampedMinutes) else {
      errorMessage = "Preset times must be different."
      return
    }

    nextValues[index] = TimerPresetConfiguration.value(forMinutes: clampedMinutes)
    setValues(nextValues)
    errorMessage = nil
  }

  private func setValues(_ values: [String]) {
    guard values.count == 3 else { return }
    preset1 = values[0]
    preset2 = values[1]
    preset3 = values[2]
  }

  private func displayName(for value: String) -> String {
    let minutes = TimerPresetConfiguration.minutes(from: value) ?? 0
    return minutes == 1 ? "1 min" : "\(minutes) min"
  }
}
