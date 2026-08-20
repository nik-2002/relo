import Foundation
import AppKit
import AVFoundation

@MainActor
final class ReloModel: ObservableObject {
  enum TimerMode {
    case countdown
    case stopwatch
  }

  @Published var remaining: TimeInterval = 0
  @Published var elapsed: TimeInterval = 0
  @Published var mode: TimerMode = .countdown
  @Published var isRunning = false
  @Published var isPaused = false
  @Published var isFinished = false
  @Published var inputDuration = ""
  @Published var inputErrorMessage: String?
  @Published private(set) var isTimeOfDayCountdown = false
  @Published private(set) var canRepeat = false

  private var timer: Timer?
  private var targetDate: Date?
  private var startDate: Date?
  private var alarmPlayer: AVAudioPlayer?
  private var alarmRepeatTimer: Timer?
  private var alarmRepeatCount = 0
  private var alarmRepeatLimit: Int?
  private let timerInterval: TimeInterval = 0.25
  private let timerTolerance: TimeInterval = 0.05
  private let alarmMinInterval: TimeInterval = 0.1
  private var lastDisplayedSecond: Int?
  private var lastInput: String?

  var formattedRemaining: String {
    let total: Int
    switch mode {
    case .stopwatch:
      total = max(0, Int(elapsed.rounded()))
    case .countdown:
      total = max(0, Int(ceil(remaining)))
    }
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let seconds = total % 60
    if hours > 0 {
      return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
    return String(format: "%02d:%02d", minutes, seconds)
  }

  var timeOfDayEndTooltip: String? {
    guard isRunning, mode == .countdown, isTimeOfDayCountdown, !isPaused, !isFinished else { return nil }
    guard let targetDate else { return nil }
    return "Ends at \(formattedTimeString(for: targetDate))"
  }

  @discardableResult
  func startFromInputs() -> Bool {
    let rawInput = inputDuration.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmed = rawInput.lowercased()
    guard !trimmed.isEmpty else {
      inputErrorMessage = nil
      return false
    }
    let parser = ReloTimerParser(defaultUnit: currentDefaultUnit())
    if trimmed == "sw" || trimmed == "stopwatch" {
      inputErrorMessage = nil
      lastInput = nil
      startStopwatch()
      inputDuration = ""
      return true
    }
    if let interval = parser.timeOfDayInterval(from: trimmed) {
      inputErrorMessage = nil
      start(duration: interval, isTimeOfDay: true)
      lastInput = rawInput
      inputDuration = ""
      updateRepeatAvailability()
      return true
    }
    let duration = parser.duration(from: trimmed)
    guard duration > 0 else {
      inputErrorMessage = "Try 10m, 1h 30m, or 6:15pm."
      return false
    }
    inputErrorMessage = nil
    start(duration: duration, isTimeOfDay: false)
    lastInput = rawInput
    inputDuration = ""
    updateRepeatAvailability()
    return true
  }

  func startFromInputs(defaultingTo defaultInput: String) -> Bool {
    guard inputDuration.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return startFromInputs()
    }
    return startPreset(defaultInput)
  }

  func start(duration: TimeInterval, isTimeOfDay: Bool = false) {
    stop()
    mode = .countdown
    remaining = duration
    isRunning = true
    isPaused = false
    isFinished = false
    isTimeOfDayCountdown = isTimeOfDay
    targetDate = Date().addingTimeInterval(duration)
    lastDisplayedSecond = nil
    scheduleTimer()
  }

  @discardableResult
  func startPreset(_ input: String) -> Bool {
    inputDuration = input
    return startFromInputs()
  }

  func startStopwatch() {
    stop()
    mode = .stopwatch
    elapsed = 0
    isRunning = true
    isPaused = false
    isFinished = false
    isTimeOfDayCountdown = false
    startDate = Date()
    lastDisplayedSecond = nil
    scheduleTimer()
  }

  func pause() {
    guard isRunning, !isPaused else { return }
    switch mode {
    case .countdown:
      if let targetDate {
        remaining = max(0, targetDate.timeIntervalSinceNow)
        // For time-of-day timers, preserve targetDate so resume can restore the
        // original absolute end time rather than computing a shifted one.
        if !isTimeOfDayCountdown {
          self.targetDate = nil
        }
      }
    case .stopwatch:
      // elapsed is only updated on whole-second tick boundaries, so it can lag
      // real time by up to one tick interval. Recompute it here or resume()
      // would rebuild startDate from a stale value and permanently lose that
      // fraction of a second on every pause/resume cycle.
      if let startDate {
        elapsed = Date().timeIntervalSince(startDate)
      }
    }
    isPaused = true
    timer?.invalidate()
    timer = nil
  }

  func resume() {
    guard isRunning, isPaused else { return }
    stopAlarm()
    guard !isFinished else { return }
    switch mode {
    case .countdown:
      if isTimeOfDayCountdown, let targetDate {
        // Recalculate from the preserved absolute end time so the timer does
        // not drift past the original target after a pause.
        remaining = max(0, targetDate.timeIntervalSinceNow)
      }
      guard remaining > 0 else {
        // Target passed while paused — complete the timer now.
        if isTimeOfDayCountdown { finish() }
        return
      }
      isPaused = false
      if !isTimeOfDayCountdown {
        targetDate = Date().addingTimeInterval(remaining)
      }
      lastDisplayedSecond = nil
      scheduleTimer()
    case .stopwatch:
      isPaused = false
      startDate = Date().addingTimeInterval(-elapsed)
      lastDisplayedSecond = nil
      scheduleTimer()
    }
  }

  func stop() {
    timer?.invalidate()
    timer = nil
    targetDate = nil
    startDate = nil
    isRunning = false
    isPaused = false
    isTimeOfDayCountdown = false
    isFinished = false
    remaining = 0
    elapsed = 0
    inputDuration = ""
    inputErrorMessage = nil
    lastInput = nil
    mode = .countdown
    lastDisplayedSecond = nil
    stopAlarm()
    updateRepeatAvailability()
  }

  private func scheduleTimer() {
    timer?.invalidate()
    let newTimer = Timer(timeInterval: timerInterval, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.tick()
      }
    }
    newTimer.tolerance = timerTolerance
    RunLoop.main.add(newTimer, forMode: .common)
    timer = newTimer
  }

  private func tick() {
    switch mode {
    case .countdown:
      guard let targetDate else { return }
      let newRemaining = targetDate.timeIntervalSinceNow
      if newRemaining <= 0 {
        finish()
      } else {
        let displaySeconds = max(0, Int(ceil(newRemaining)))
        if displaySeconds != lastDisplayedSecond {
          remaining = newRemaining
          lastDisplayedSecond = displaySeconds
        }
      }
    case .stopwatch:
      guard let startDate else { return }
      let newElapsed = Date().timeIntervalSince(startDate)
      let displaySeconds = max(0, Int(newElapsed.rounded()))
      if displaySeconds != lastDisplayedSecond {
        elapsed = newElapsed
        lastDisplayedSecond = displaySeconds
      }
    }
  }

  private func finish() {
    timer?.invalidate()
    timer = nil
    remaining = 0
    isRunning = true
    isPaused = true
    isTimeOfDayCountdown = false
    isFinished = true
    targetDate = nil
    mode = .countdown
    startAlarm()
    updateRepeatAvailability()
  }

  private func formattedTimeString(for date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale.current
    formatter.timeStyle = .short
    formatter.dateStyle = .none
    return formatter.string(from: date)
      .replacingOccurrences(of: "AM", with: "a.m.")
      .replacingOccurrences(of: "PM", with: "p.m.")
      .replacingOccurrences(of: "am", with: "a.m.")
      .replacingOccurrences(of: "pm", with: "p.m.")
  }

  private func startAlarm() {
    stopAlarm()
    let configuration = AlarmConfiguration.load()
    guard configuration.playsSound else { return }
    alarmRepeatCount = 0
    alarmRepeatLimit = configuration.repeatLimit

    let selectedURL = configuration.tone.audioURL
    let fallbackURL = AlarmTone.bundled(.default).audioURL
    guard let url = selectedURL ?? fallbackURL else { return }

    let playbackDuration: TimeInterval
    do {
      let player = try AVAudioPlayer(contentsOf: url)
      player.volume = configuration.volume
      alarmPlayer = player
      playbackDuration = player.duration
    } catch {
      guard url != fallbackURL,
            let fallbackURL,
            let fallbackPlayer = try? AVAudioPlayer(contentsOf: fallbackURL) else {
        alarmPlayer = nil
        return
      }
      fallbackPlayer.volume = configuration.volume
      alarmPlayer = fallbackPlayer
      playbackDuration = fallbackPlayer.duration
    }

    playAlarmOnce()
    alarmRepeatCount = 1

    guard alarmRepeatLimit != 1 else { return }

    let interval = max(alarmMinInterval, playbackDuration)
    let repeatTimer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self else { return }
        if let alarmRepeatLimit = self.alarmRepeatLimit,
           self.alarmRepeatCount >= alarmRepeatLimit {
          self.stopAlarm()
          return
        }
        self.playAlarmOnce()
        self.alarmRepeatCount += 1
      }
    }
    RunLoop.main.add(repeatTimer, forMode: .common)
    alarmRepeatTimer = repeatTimer
  }

  private func playAlarmOnce() {
    alarmPlayer?.currentTime = 0
    alarmPlayer?.play()
  }

  private func stopAlarm() {
    alarmRepeatTimer?.invalidate()
    alarmRepeatTimer = nil
    alarmPlayer?.stop()
    alarmPlayer = nil
    alarmRepeatCount = 0
    alarmRepeatLimit = nil
  }

  @discardableResult
  func repeatLastInput() -> Bool {
    guard let lastInput else { return false }
    inputDuration = lastInput
    return startFromInputs()
  }

  private func updateRepeatAvailability() {
    canRepeat = isFinished && lastInput != nil
  }

  private func currentDefaultUnit() -> DefaultTimeUnit {
    let raw = UserDefaults.standard.string(forKey: ReloSettingsKeys.defaultUnit)
    return DefaultTimeUnit(rawValue: raw ?? "") ?? .default
  }
}
