import XCTest
@testable import Relo

final class ReloTimerParserTests: XCTestCase {
  func testDurationFormats() {
    let parser = ReloTimerParser(defaultUnit: .minutes)

    XCTAssertEqual(parser.duration(from: "10"), 600)
    XCTAssertEqual(parser.duration(from: "45s"), 45)
    XCTAssertEqual(parser.duration(from: "1.5 hours"), 5_400)
    XCTAssertEqual(parser.duration(from: "1h 30m"), 5_400)
    XCTAssertEqual(parser.duration(from: "17m 45s"), 1_065)
    XCTAssertEqual(parser.duration(from: "25:00"), 1_500)
    XCTAssertEqual(parser.duration(from: ":45"), 45)
    XCTAssertEqual(parser.duration(from: "1:02:03"), 3_723)
  }

  func testDefaultUnitIsAppliedOnlyWhenUnitIsMissing() {
    XCTAssertEqual(ReloTimerParser(defaultUnit: .seconds).duration(from: "2"), 2)
    XCTAssertEqual(ReloTimerParser(defaultUnit: .minutes).duration(from: "2"), 120)
    XCTAssertEqual(ReloTimerParser(defaultUnit: .hours).duration(from: "2"), 7_200)
    XCTAssertEqual(ReloTimerParser(defaultUnit: .hours).duration(from: "2m"), 120)
  }

  func testInvalidDurationsReturnZero() {
    let parser = ReloTimerParser(defaultUnit: .minutes)

    XCTAssertEqual(parser.duration(from: "later"), 0)
    XCTAssertEqual(parser.duration(from: "10 elephants"), 0)
    XCTAssertEqual(parser.duration(from: "1:60"), 0)
    XCTAssertEqual(parser.duration(from: "0"), 0)
    XCTAssertEqual(parser.duration(from: ""), 0)
  }

  func testTimeOfDayFormatsAndNextDayRollover() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
    let parser = ReloTimerParser(defaultUnit: .minutes, calendar: calendar)
    let now = try XCTUnwrap(calendar.date(from: DateComponents(
      year: 2026,
      month: 7,
      day: 17,
      hour: 17,
      minute: 0
    )))

    XCTAssertEqual(parser.timeOfDayInterval(from: "6:15pm", now: now), 4_500)
    XCTAssertEqual(parser.timeOfDayInterval(from: "615p", now: now), 4_500)
    XCTAssertEqual(parser.timeOfDayInterval(from: "6:15 am", now: now), 47_700)
    XCTAssertEqual(parser.timeOfDayInterval(from: "midnight", now: now), 25_200)
  }

  func testInvalidTimeOfDayReturnsNil() {
    let parser = ReloTimerParser(defaultUnit: .minutes)

    XCTAssertNil(parser.timeOfDayInterval(from: "25:00pm"))
    XCTAssertNil(parser.timeOfDayInterval(from: "sometime"))
  }

  @MainActor
  func testInvalidModelInputProvidesMinimalGuidance() {
    let model = ReloModel()
    model.inputDuration = "later"

    XCTAssertFalse(model.startFromInputs())
    XCTAssertEqual(model.inputErrorMessage, "Try 10m, 1h 30m, or 6:15pm.")
  }

  @MainActor
  func testPresetStartsImmediatelyUsingTheNormalTimerPath() {
    let model = ReloModel()

    XCTAssertTrue(model.startPreset("3m"))
    XCTAssertTrue(model.isRunning)
    XCTAssertEqual(model.remaining, 180)
    XCTAssertEqual(model.inputDuration, "")

    model.stop()
  }

  @MainActor
  func testEmptyInputStartsTheDisplayedDefaultPreset() {
    let model = ReloModel()

    XCTAssertTrue(model.startFromInputs(defaultingTo: "20m"))
    XCTAssertTrue(model.isRunning)
    XCTAssertEqual(model.remaining, 1_200, accuracy: 0.01)
    XCTAssertEqual(model.inputDuration, "")

    model.stop()
  }

  @MainActor
  func testTypedInputOverridesTheDisplayedDefaultPreset() {
    let model = ReloModel()
    model.inputDuration = "3m"

    XCTAssertTrue(model.startFromInputs(defaultingTo: "20m"))
    XCTAssertEqual(model.remaining, 180, accuracy: 0.01)

    model.stop()
  }
}

final class TimerPresetConfigurationTests: XCTestCase {
  private var defaults: UserDefaults!
  private let suiteName = "ReloTests.TimerPresets"

  override func setUp() {
    super.setUp()
    defaults = UserDefaults(suiteName: suiteName)
    defaults.removePersistentDomain(forName: suiteName)
  }

  override func tearDown() {
    defaults.removePersistentDomain(forName: suiteName)
    defaults = nil
    super.tearDown()
  }

  func testDefaultPresetsAreFiveTenAndTwentyFiveMinutes() {
    let values = TimerPresetConfiguration.storedValues(defaults: defaults)
    let presets = TimerPresetConfiguration.presets(from: values, defaultUnit: .minutes)

    XCTAssertEqual(values, ["5m", "10m", "25m"])
    XCTAssertEqual(presets.map(\.duration), [300, 600, 1_500])
    XCTAssertEqual(presets.map(\.displayName), ["5m", "10m", "25m"])
  }

  func testSupportedPresetsAreSavedForButtons() {
    let values = ["7m", "42m", "120m"]

    TimerPresetConfiguration.save(values, defaults: defaults)

    let stored = TimerPresetConfiguration.storedValues(defaults: defaults)
    let presets = TimerPresetConfiguration.presets(from: stored, defaultUnit: .minutes)
    XCTAssertEqual(stored, values)
    XCTAssertEqual(presets.map(\.displayName), ["7m", "42m", "2h"])
  }

  func testPresetInputsSupportExactMinutesWithinOneDay() {
    XCTAssertEqual(TimerPresetConfiguration.minuteRange, 1...1_440)
    XCTAssertEqual(TimerPresetConfiguration.minutes(from: "42m"), 42)
    XCTAssertEqual(TimerPresetConfiguration.value(forMinutes: 90), "90m")
    XCTAssertEqual(TimerPresetConfiguration.value(forMinutes: 0), "1m")
    XCTAssertEqual(TimerPresetConfiguration.value(forMinutes: 2_000), "1440m")
    XCTAssertEqual(TimerPresetConfiguration.steppedMinutes(from: 25, direction: 1), 26)
    XCTAssertEqual(TimerPresetConfiguration.steppedMinutes(from: 25, direction: -1), 24)
    XCTAssertEqual(TimerPresetConfiguration.steppedMinutes(from: 1, direction: -1), 1)
    XCTAssertEqual(
      TimerPresetConfiguration.largestPresetValue(from: ["20m", "5m", "10m"]),
      "20m"
    )
    XCTAssertEqual(TimerPresetConfiguration.statusDisplayText(forPresetValue: "20m"), "20:00")
    XCTAssertEqual(TimerPresetConfiguration.statusDisplayText(forPresetValue: "90m"), "01:30:00")
  }

  func testPresetUserInputAcceptsOnlyDigitsAndClampsToRange() {
    XCTAssertEqual(TimerPresetConfiguration.minutes(fromUserInput: "123"), 123)
    XCTAssertEqual(TimerPresetConfiguration.minutes(fromUserInput: "0"), 1)
    XCTAssertEqual(TimerPresetConfiguration.minutes(fromUserInput: "2000"), 1_440)

    for invalidValue in ["", "25m", "1.5", "-5", "ten", "1 0", "5lkj"] {
      XCTAssertNil(TimerPresetConfiguration.minutes(fromUserInput: invalidValue))
    }
  }

  func testPreviousUntouchedDefaultsMigrateToTwentyFiveMinutes() {
    defaults.set("1m", forKey: ReloSettingsKeys.timerPreset1)
    defaults.set("5m", forKey: ReloSettingsKeys.timerPreset2)
    defaults.set("10m", forKey: ReloSettingsKeys.timerPreset3)
    defaults.set("30m", forKey: ReloSettingsKeys.timerPreset4)

    TimerPresetConfiguration.prepareDefaultsIfNeeded(defaults: defaults)

    XCTAssertEqual(
      TimerPresetConfiguration.storedValues(defaults: defaults),
      ["5m", "10m", "25m"]
    )
    XCTAssertNil(defaults.string(forKey: ReloSettingsKeys.timerPreset4))
  }

  func testPresetDefaultMigrationPreservesCustomChoices() {
    let customValues = ["7m", "42m", "120m"]
    TimerPresetConfiguration.save(customValues, defaults: defaults)
    defaults.set("30m", forKey: ReloSettingsKeys.timerPreset4)

    TimerPresetConfiguration.prepareDefaultsIfNeeded(defaults: defaults)

    XCTAssertEqual(
      TimerPresetConfiguration.storedValues(defaults: defaults),
      customValues
    )
    XCTAssertNil(defaults.string(forKey: ReloSettingsKeys.timerPreset4))
  }

  func testUnsupportedOrDuplicatePresetsFallBackToDefaults() {
    XCTAssertEqual(
      TimerPresetConfiguration.resolvedValues(
        from: ["5m", "5m", "25m"]
      ),
      TimerPresetConfiguration.defaultValues
    )
    XCTAssertEqual(
      TimerPresetConfiguration.resolvedValues(
        from: ["5m", "10m", "1441m"]
      ),
      TimerPresetConfiguration.defaultValues
    )
  }
}

final class AlarmConfigurationTests: XCTestCase {
  private var defaults: UserDefaults!
  private let suiteName = "ReloTests.AlarmConfiguration"
  private var toneDirectoryURL: URL!
  private var importedToneStore: ImportedToneStore!

  override func setUp() {
    super.setUp()
    defaults = UserDefaults(suiteName: suiteName)
    defaults.removePersistentDomain(forName: suiteName)
    toneDirectoryURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("ReloToneTests-\(UUID().uuidString)", isDirectory: true)
    importedToneStore = ImportedToneStore(directoryURL: toneDirectoryURL)
  }

  override func tearDown() {
    defaults.removePersistentDomain(forName: suiteName)
    try? FileManager.default.removeItem(at: toneDirectoryURL)
    importedToneStore = nil
    toneDirectoryURL = nil
    defaults = nil
    super.tearDown()
  }

  func testDefaultsPlayTheStandardAlarmTenTimes() {
    let configuration = AlarmConfiguration.load(defaults: defaults)

    XCTAssertTrue(configuration.playsSound)
    XCTAssertEqual(configuration.tone, .bundled(.wakeUp))
    XCTAssertEqual(configuration.repeatLimit, 10)
    XCTAssertEqual(configuration.volume, Float(AlarmVolume.defaultLevel))
  }

  func testSilentAndCustomAlarmSettingsAreLoaded() {
    defaults.set(false, forKey: ReloSettingsKeys.playSound)
    defaults.set(NotificationTone.discreet.rawValue, forKey: ReloSettingsKeys.tone)
    defaults.set(NotificationRepeatOption.infinite.rawValue, forKey: ReloSettingsKeys.repeatCount)
    defaults.set(LegacyNotificationVolume.high.rawValue, forKey: ReloSettingsKeys.volume)

    let configuration = AlarmConfiguration.load(defaults: defaults)

    XCTAssertFalse(configuration.playsSound)
    XCTAssertEqual(configuration.tone, .bundled(.discreet))
    XCTAssertNil(configuration.repeatLimit)
    XCTAssertEqual(configuration.volume, Float(LegacyNotificationVolume.high.level))
  }

  func testContinuousAlarmVolumeIsLoadedAndClamped() {
    defaults.set(0.42, forKey: ReloSettingsKeys.volumeLevel)
    XCTAssertEqual(AlarmConfiguration.load(defaults: defaults).volume, 0.42, accuracy: 0.001)

    defaults.set(1.4, forKey: ReloSettingsKeys.volumeLevel)
    XCTAssertEqual(AlarmConfiguration.load(defaults: defaults).volume, 1.0)
  }

  func testLegacyAlarmVolumeMigratesToSliderLevel() {
    defaults.set(LegacyNotificationVolume.low.rawValue, forKey: ReloSettingsKeys.volume)

    let migratedLevel = AlarmVolume.migrateIfNeeded(defaults: defaults)

    XCTAssertEqual(migratedLevel, LegacyNotificationVolume.low.level)
    XCTAssertEqual(
      defaults.double(forKey: ReloSettingsKeys.volumeLevel),
      LegacyNotificationVolume.low.level
    )
  }

  func testBundledToneSetStaysFocused() {
    XCTAssertEqual(
      NotificationTone.allCases,
      [.bedsideClock, .digitalTone, .discreet, .joyousChime, .wakeUp]
    )
    XCTAssertEqual(NotificationTone.bedsideClock.displayName, "Bedside Clock")
    XCTAssertEqual(NotificationTone.digitalTone.displayName, "Digital Tone")
    XCTAssertEqual(NotificationTone.bedsideClock.fileExtension, "mp3")
    XCTAssertEqual(NotificationTone.digitalTone.fileExtension, "mp3")
  }

  func testImportedToneIsCopiedAndLoadedWithoutChangingOtherAlarmSettings() throws {
    let sourceURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("Kitchen Bell.m4r")
    try Data("test audio".utf8).write(to: sourceURL)
    defer { try? FileManager.default.removeItem(at: sourceURL) }

    let importedTone = try importedToneStore.importTone(from: sourceURL, defaults: defaults)
    defaults.set(ImportedToneStore.selectionValue, forKey: ReloSettingsKeys.tone)
    defaults.set(NotificationRepeatOption.five.rawValue, forKey: ReloSettingsKeys.repeatCount)
    defaults.set(LegacyNotificationVolume.low.rawValue, forKey: ReloSettingsKeys.volume)

    let configuration = AlarmConfiguration.load(
      defaults: defaults,
      importedToneStore: importedToneStore
    )

    XCTAssertEqual(configuration.tone, .imported(importedTone))
    XCTAssertEqual(importedTone.displayName, "Kitchen Bell")
    XCTAssertTrue(FileManager.default.fileExists(atPath: importedTone.url.path))
    XCTAssertNotEqual(importedTone.url, sourceURL)
    XCTAssertEqual(configuration.repeatLimit, 5)
    XCTAssertEqual(configuration.volume, Float(LegacyNotificationVolume.low.level))
  }

  func testReplacingAndRemovingImportedToneManagesOnlyRelosCopies() throws {
    let firstSourceURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("First Tone.wav")
    let secondSourceURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("Second Tone.aiff")
    try Data("first".utf8).write(to: firstSourceURL)
    try Data("second".utf8).write(to: secondSourceURL)
    defer {
      try? FileManager.default.removeItem(at: firstSourceURL)
      try? FileManager.default.removeItem(at: secondSourceURL)
    }

    let firstTone = try importedToneStore.importTone(from: firstSourceURL, defaults: defaults)
    let secondTone = try importedToneStore.importTone(from: secondSourceURL, defaults: defaults)

    XCTAssertFalse(FileManager.default.fileExists(atPath: firstTone.url.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: secondTone.url.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: firstSourceURL.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: secondSourceURL.path))

    try importedToneStore.remove(defaults: defaults)

    XCTAssertNil(importedToneStore.current(defaults: defaults))
    XCTAssertFalse(FileManager.default.fileExists(atPath: secondTone.url.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: secondSourceURL.path))
  }

  func testMissingImportedToneFallsBackToReloDefault() {
    defaults.set(ImportedToneStore.selectionValue, forKey: ReloSettingsKeys.tone)
    defaults.set("Missing.wav", forKey: ReloSettingsKeys.importedToneFileName)

    let configuration = AlarmConfiguration.load(
      defaults: defaults,
      importedToneStore: importedToneStore
    )

    XCTAssertEqual(configuration.tone, .bundled(.default))
  }
}
