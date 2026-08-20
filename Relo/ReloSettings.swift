import Foundation

enum ReloSettingsKeys {
  static let tone = "notificationTone"
  static let repeatCount = "notificationRepeatCount"
  // Retained only to migrate the former Very Low/Low/Medium/High setting.
  static let volume = "notificationVolume"
  static let volumeLevel = "notificationVolumeLevel"
  static let playSound = "playSound"
  static let defaultUnit = "defaultTimeUnit"
  static let openHotkey = "hotkeyOpen"
  static let pauseResumeHotkey = "hotkeyPauseResume"
  static let clearHotkey = "hotkeyClear"
  static let unifiedHotkeyStorage = "unifiedHotkeyStorageV1"
  static let didPromptLoginItem = "didPromptLoginItem"
  static let importedToneFileName = "importedToneFileName"
  static let importedToneDisplayName = "importedToneDisplayName"
  static let timerPreset1 = "timerPreset1"
  static let timerPreset2 = "timerPreset2"
  static let timerPreset3 = "timerPreset3"
  static let timerPreset4 = "timerPreset4"
  static let timerPresetDefaultsVersion = "timerPresetDefaultsVersion"
  static let floatingCountdownDisplayEnabled = "floatingCountdownDisplayEnabled"
  static let floatingCountdownOrigin = "floatingCountdownOrigin"
}

enum NotificationTone: String, CaseIterable, Identifiable {
  case bedsideClock = "bedside-clock"
  case digitalTone = "digital-tone"
  case discreet
  case joyousChime = "joyous-chime"
  case wakeUp = "wake-up"

  static let `default` = NotificationTone.wakeUp

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .bedsideClock:
      return "Bedside Clock"
    case .digitalTone:
      return "Digital Tone"
    case .discreet:
      return "Discreet"
    case .joyousChime:
      return "Joyous Chime"
    case .wakeUp:
      return "Wake Up"
    }
  }

  var fileExtension: String {
    switch self {
    case .bedsideClock, .digitalTone:
      return "mp3"
    case .discreet, .joyousChime, .wakeUp:
      return "wav"
    }
  }

  var audioURL: URL? {
    Bundle.main.url(forResource: rawValue, withExtension: fileExtension)
  }
}

enum NotificationRepeatOption: Int, CaseIterable, Identifiable {
  case none = 0
  case five = 5
  case ten = 10
  case infinite = -1

  static let `default` = NotificationRepeatOption.ten

  var id: Int { rawValue }

  var displayName: String {
    switch self {
    case .none:
      return "Once"
    case .five:
      return "5 Times"
    case .ten:
      return "10 Times"
    case .infinite:
      return "Until Cleared"
    }
  }

  var repeatLimit: Int? {
    switch self {
    case .none:
      return 1
    case .five:
      return 5
    case .ten:
      return 10
    case .infinite:
      return nil
    }
  }
}

enum LegacyNotificationVolume: String {
  case ultraLow = "ultra-low"
  case low
  case medium
  case high

  var level: Double {
    switch self {
    case .ultraLow:
      return 0.2
    case .low:
      return 0.35
    case .medium:
      return 0.7
    case .high:
      return 1.0
    }
  }
}

enum AlarmVolume {
  static let defaultLevel = 0.7

  static func load(defaults: UserDefaults = .standard) -> Double {
    if let storedLevel = defaults.object(forKey: ReloSettingsKeys.volumeLevel) as? NSNumber {
      return clamped(storedLevel.doubleValue)
    }

    let legacyValue = defaults.string(forKey: ReloSettingsKeys.volume)
    return LegacyNotificationVolume(rawValue: legacyValue ?? "")?.level ?? defaultLevel
  }

  @discardableResult
  static func migrateIfNeeded(defaults: UserDefaults = .standard) -> Double {
    let level = load(defaults: defaults)
    if defaults.object(forKey: ReloSettingsKeys.volumeLevel) == nil {
      defaults.set(level, forKey: ReloSettingsKeys.volumeLevel)
    }
    return level
  }

  static func clamped(_ level: Double) -> Double {
    min(max(level, 0), 1)
  }
}

enum DefaultTimeUnit: String, CaseIterable, Identifiable {
  case seconds
  case minutes
  case hours

  static let `default` = DefaultTimeUnit.minutes

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .seconds:
      return "Seconds"
    case .minutes:
      return "Minutes"
    case .hours:
      return "Hours"
    }
  }

  var multiplier: Double {
    switch self {
    case .seconds:
      return 1
    case .minutes:
      return 60
    case .hours:
      return 3600
    }
  }
}

struct TimerPreset: Identifiable, Equatable {
  let slot: Int
  let input: String
  let duration: TimeInterval

  var id: Int { slot }

  var displayName: String {
    let totalSeconds = max(1, Int(duration.rounded()))
    if totalSeconds % 3_600 == 0 {
      return "\(totalSeconds / 3_600)h"
    }
    if totalSeconds % 60 == 0 {
      return "\(totalSeconds / 60)m"
    }
    if totalSeconds < 60 {
      return "\(totalSeconds)s"
    }

    let hours = totalSeconds / 3_600
    let minutes = (totalSeconds % 3_600) / 60
    let seconds = totalSeconds % 60
    if hours > 0 {
      return seconds == 0 ? "\(hours)h\(minutes)m" : "\(hours)h\(minutes)m\(seconds)s"
    }
    return "\(minutes)m\(seconds)s"
  }
}

enum TimerPresetConfiguration {
  static let defaultValues = ["5m", "10m", "25m"]
  static let minuteRange = 1...1_440
  private static let previousDefaultValues = [
    ["1m", "5m", "10m", "30m"],
    ["1m", "5m", "10m", "25m"],
  ]
  private static let currentDefaultsVersion = 3
  static let keys = [
    ReloSettingsKeys.timerPreset1,
    ReloSettingsKeys.timerPreset2,
    ReloSettingsKeys.timerPreset3,
  ]
  private static let legacyKeys = keys + [ReloSettingsKeys.timerPreset4]

  static func storedValues(defaults: UserDefaults = .standard) -> [String] {
    let values = zip(keys, defaultValues).map { key, fallback in
      defaults.string(forKey: key) ?? fallback
    }
    return resolvedValues(from: values)
  }

  static func prepareDefaultsIfNeeded(defaults: UserDefaults = .standard) {
    guard defaults.integer(forKey: ReloSettingsKeys.timerPresetDefaultsVersion)
      < currentDefaultsVersion else { return }

    let legacyValues = zip(legacyKeys, previousDefaultValues[1]).map { key, fallback in
      defaults.string(forKey: key) ?? fallback
    }
    if previousDefaultValues.contains(legacyValues) {
      save(defaultValues, defaults: defaults)
    } else {
      save(resolvedValues(from: Array(legacyValues.prefix(keys.count))), defaults: defaults)
    }
    defaults.removeObject(forKey: ReloSettingsKeys.timerPreset4)
    defaults.set(
      currentDefaultsVersion,
      forKey: ReloSettingsKeys.timerPresetDefaultsVersion
    )
  }

  static func resolvedValues(from values: [String]) -> [String] {
    let minutes = values.compactMap(minutes(from:))
    guard values.count == keys.count,
          minutes.count == keys.count,
          Set(minutes).count == keys.count else {
      return defaultValues
    }
    return minutes.map(value(forMinutes:))
  }

  static func largestPresetValue(from values: [String]) -> String {
    resolvedValues(from: values).max { first, second in
      (minutes(from: first) ?? 0) < (minutes(from: second) ?? 0)
    } ?? defaultValues[2]
  }

  static func largestStoredPresetValue(defaults: UserDefaults = .standard) -> String {
    largestPresetValue(from: storedValues(defaults: defaults))
  }

  static func statusDisplayText(forPresetValue value: String) -> String {
    let minutes = minutes(from: value) ?? 25
    let hours = minutes / 60
    let remainingMinutes = minutes % 60
    if hours > 0 {
      return String(format: "%02d:%02d:00", hours, remainingMinutes)
    }
    return String(format: "%02d:00", minutes)
  }

  static func idleStatusDisplayText(defaults: UserDefaults = .standard) -> String {
    statusDisplayText(forPresetValue: largestStoredPresetValue(defaults: defaults))
  }

  static func minutes(from value: String) -> Int? {
    guard value.hasSuffix("m"),
          let minutes = Int(value.dropLast()),
          minuteRange.contains(minutes) else { return nil }
    return minutes
  }

  static func minutes(fromUserInput input: String) -> Int? {
    guard !input.isEmpty,
          input.unicodeScalars.allSatisfy({ (48...57).contains($0.value) }),
          let minutes = Int(input) else { return nil }
    return clampedMinutes(minutes)
  }

  static func value(forMinutes minutes: Int) -> String {
    "\(clampedMinutes(minutes))m"
  }

  static func clampedMinutes(_ minutes: Int) -> Int {
    min(max(minutes, minuteRange.lowerBound), minuteRange.upperBound)
  }

  static func steppedMinutes(from minutes: Int, direction: Int) -> Int {
    guard direction != 0 else { return clampedMinutes(minutes) }
    return clampedMinutes(minutes + (direction > 0 ? 1 : -1))
  }

  static func presets(
    from values: [String],
    defaultUnit: DefaultTimeUnit
  ) -> [TimerPreset] {
    let parser = ReloTimerParser(defaultUnit: defaultUnit)
    return values.prefix(keys.count).enumerated().compactMap { slot, value in
      let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
      let duration = parser.duration(from: trimmed)
      guard duration > 0 else { return nil }
      return TimerPreset(slot: slot, input: trimmed, duration: duration)
    }
  }

  static func uniquePresets(
    from values: [String],
    defaultUnit: DefaultTimeUnit
  ) -> [TimerPreset] {
    var seenDurations = Set<Int>()
    return presets(from: values, defaultUnit: defaultUnit).filter { preset in
      seenDurations.insert(Int((preset.duration * 1_000).rounded())).inserted
    }
  }

  static func save(
    _ values: [String],
    defaults: UserDefaults = .standard
  ) {
    let resolvedValues = resolvedValues(from: values)
    for (key, value) in zip(keys, resolvedValues) {
      defaults.set(value, forKey: key)
    }
  }
}

struct ImportedTone: Equatable {
  let fileName: String
  let displayName: String
  let url: URL
}

struct ImportedToneStore {
  static let selectionValue = "imported"

  let directoryURL: URL

  init(directoryURL: URL? = nil) {
    if let directoryURL {
      self.directoryURL = directoryURL
      return
    }
    let applicationSupport = FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
    self.directoryURL = applicationSupport
      .appendingPathComponent("Relo", isDirectory: true)
      .appendingPathComponent("Tones", isDirectory: true)
  }

  func current(defaults: UserDefaults = .standard) -> ImportedTone? {
    guard let storedFileName = defaults.string(forKey: ReloSettingsKeys.importedToneFileName) else {
      return nil
    }
    let fileName = URL(fileURLWithPath: storedFileName).lastPathComponent
    guard fileName == storedFileName else { return nil }
    let url = directoryURL.appendingPathComponent(fileName)
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    let storedDisplayName = defaults.string(forKey: ReloSettingsKeys.importedToneDisplayName)
    let fallbackName = url.deletingPathExtension().lastPathComponent
    let displayName = storedDisplayName.flatMap { $0.isEmpty ? nil : $0 } ?? fallbackName
    return ImportedTone(
      fileName: fileName,
      displayName: displayName,
      url: url
    )
  }

  func importTone(from sourceURL: URL, defaults: UserDefaults = .standard) throws -> ImportedTone {
    try FileManager.default.createDirectory(
      at: directoryURL,
      withIntermediateDirectories: true
    )

    let fileExtension = sourceURL.pathExtension.lowercased()
    let suffix = fileExtension.isEmpty ? "audio" : fileExtension
    let fileName = "Imported-\(UUID().uuidString).\(suffix)"
    let destinationURL = directoryURL.appendingPathComponent(fileName)
    try FileManager.default.copyItem(at: sourceURL, to: destinationURL)

    let previousTone = current(defaults: defaults)
    let proposedDisplayName = sourceURL.deletingPathExtension().lastPathComponent
    let displayName = proposedDisplayName.isEmpty ? "Imported Tone" : proposedDisplayName
    defaults.set(fileName, forKey: ReloSettingsKeys.importedToneFileName)
    defaults.set(displayName, forKey: ReloSettingsKeys.importedToneDisplayName)

    if let previousTone, previousTone.url != destinationURL {
      try? FileManager.default.removeItem(at: previousTone.url)
    }

    return ImportedTone(fileName: fileName, displayName: displayName, url: destinationURL)
  }

  func remove(defaults: UserDefaults = .standard) throws {
    if let tone = current(defaults: defaults) {
      try FileManager.default.removeItem(at: tone.url)
    }
    defaults.removeObject(forKey: ReloSettingsKeys.importedToneFileName)
    defaults.removeObject(forKey: ReloSettingsKeys.importedToneDisplayName)
  }
}

enum AlarmTone: Equatable {
  case bundled(NotificationTone)
  case imported(ImportedTone)

  var audioURL: URL? {
    switch self {
    case .bundled(let tone):
      return tone.audioURL
    case .imported(let tone):
      return tone.url
    }
  }
}

struct AlarmConfiguration {
  let playsSound: Bool
  let tone: AlarmTone
  let repeatLimit: Int?
  let volume: Float

  static func load(
    defaults: UserDefaults = .standard,
    importedToneStore: ImportedToneStore = ImportedToneStore()
  ) -> AlarmConfiguration {
    let playsSound = defaults.object(forKey: ReloSettingsKeys.playSound) as? Bool ?? true
    let toneRawValue = defaults.string(forKey: ReloSettingsKeys.tone)
    let tone: AlarmTone
    if toneRawValue == ImportedToneStore.selectionValue,
       let importedTone = importedToneStore.current(defaults: defaults) {
      tone = .imported(importedTone)
    } else {
      tone = .bundled(NotificationTone(rawValue: toneRawValue ?? "") ?? .default)
    }
    let storedRepeatCount = defaults.object(forKey: ReloSettingsKeys.repeatCount) as? Int
    let repeatOption = NotificationRepeatOption(
      rawValue: storedRepeatCount ?? NotificationRepeatOption.default.rawValue
    ) ?? .default
    let volume = AlarmVolume.load(defaults: defaults)

    return AlarmConfiguration(
      playsSound: playsSound,
      tone: tone,
      repeatLimit: repeatOption.repeatLimit,
      volume: Float(volume)
    )
  }
}
