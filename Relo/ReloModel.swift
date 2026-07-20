import Foundation
import AppKit
import AVFoundation
import UserNotifications

final class ReloModel: ObservableObject {
  enum TimerMode {
    case countdown
    case stopwatch
  }

  private enum NotificationContext {
    case duration(TimeInterval)
    case timeOfDay(String)
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
  private var notificationContext: NotificationContext?
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
    let formatter = DateFormatter()
    formatter.locale = Locale.current
    formatter.timeStyle = .short
    formatter.dateStyle = .none
    let timeString = formatter.string(from: targetDate)
      .replacingOccurrences(of: "AM", with: "a.m.")
      .replacingOccurrences(of: "PM", with: "p.m.")
      .replacingOccurrences(of: "am", with: "a.m.")
      .replacingOccurrences(of: "pm", with: "p.m.")
    return "Ends at \(timeString)"
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
      notificationContext = nil
      lastInput = nil
      startStopwatch()
      inputDuration = ""
      return true
    }
    if let interval = parser.timeOfDayInterval(from: trimmed) {
      inputErrorMessage = nil
      notificationContext = .timeOfDay(rawInput)
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
    notificationContext = .duration(duration)
    start(duration: duration, isTimeOfDay: false)
    lastInput = rawInput
    inputDuration = ""
    updateRepeatAvailability()
    return true
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
    if isTimeOfDay {
      if notificationContext == nil, let targetDate {
        notificationContext = .timeOfDay(formattedTimeString(for: targetDate))
      }
    } else {
      notificationContext = .duration(duration)
    }
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
    notificationContext = nil
    scheduleTimer()
  }

  func pause() {
    guard isRunning, !isPaused else { return }
    if mode == .countdown, let targetDate {
      remaining = max(0, targetDate.timeIntervalSinceNow)
      // For time-of-day timers, preserve targetDate so resume can restore the
      // original absolute end time rather than computing a shifted one.
      if !isTimeOfDayCountdown {
        self.targetDate = nil
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
      // notificationContext already holds the original user input; no update needed.
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
    notificationContext = nil
    stopAlarm()
    updateRepeatAvailability()
  }

  private func scheduleTimer() {
    timer?.invalidate()
    let newTimer = Timer(timeInterval: timerInterval, repeats: true) { [weak self] _ in
      self?.tick()
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
    let context = notificationContext
    notificationContext = nil
    sendFinishedNotificationIfNeeded(context: context)
    startAlarm()
    updateRepeatAvailability()
  }

  private func sendFinishedNotificationIfNeeded(context: NotificationContext?) {
    guard UserDefaults.standard.bool(forKey: ReloSettingsKeys.showNotifications) else { return }
    guard let context else { return }

    let body: String
    switch context {
    case .duration(let duration):
      body = formattedDurationDescription(duration)
    case .timeOfDay(let input):
      let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
      let timeString = trimmed.isEmpty ? formattedTimeString(for: Date()) : trimmed
      body = "Reached \(timeString)"
    }

    let content = UNMutableNotificationContent()
    content.title = "Timer Finished"
    content.body = body
    content.categoryIdentifier = NotificationIdentifiers.timerFinishedCategory

    let request = UNNotificationRequest(
      identifier: UUID().uuidString,
      content: content,
      trigger: nil
    )
    UNUserNotificationCenter.current().add(request)
  }

  private func formattedDurationDescription(_ duration: TimeInterval) -> String {
    let totalSeconds = max(1, Int(ceil(duration)))
    if totalSeconds < 60 {
      return "\(formattedUnit(totalSeconds, unit: "second")) timer"
    }

    let totalMinutes = Int(ceil(duration / 60.0))
    if totalMinutes < 60 {
      return "\(formattedUnit(totalMinutes, unit: "minute")) timer"
    }

    let hours = totalMinutes / 60
    let minutes = totalMinutes % 60
    let hoursPart = formattedUnit(hours, unit: "hour")
    if minutes == 0 {
      return "\(hoursPart) timer"
    }
    let minutesPart = formattedUnit(minutes, unit: "minute")
    return "\(hoursPart) \(minutesPart) timer"
  }

  private func formattedUnit(_ value: Int, unit: String) -> String {
    let label = value == 1 ? unit : "\(unit)s"
    return "\(value)-\(label)"
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
      guard let self else { return }
      if let alarmRepeatLimit = self.alarmRepeatLimit,
         self.alarmRepeatCount >= alarmRepeatLimit {
        self.stopAlarm()
        return
      }
      self.playAlarmOnce()
      self.alarmRepeatCount += 1
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
