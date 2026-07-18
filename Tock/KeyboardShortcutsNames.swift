import Foundation

#if canImport(KeyboardShortcuts)
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
  static let openRecorder = Self("hotkeyOpenRecorder")
  static let pauseResumeRecorder = Self("hotkeyPauseResumeRecorder")
  static let clearRecorder = Self("hotkeyClearRecorder")
  static let legacyOpenRecorder = Self(TockSettingsKeys.openHotkey)
  static let legacyClearRecorder = Self(TockSettingsKeys.clearHotkey)
}

extension HotkeyAction {
  var recorderName: KeyboardShortcuts.Name {
    switch self {
    case .open:
      return .openRecorder
    case .pauseResume:
      return .pauseResumeRecorder
    case .clear:
      return .clearRecorder
    }
  }

  var legacyRecorderName: KeyboardShortcuts.Name? {
    switch self {
    case .open:
      return .legacyOpenRecorder
    case .pauseResume:
      return nil
    case .clear:
      return .legacyClearRecorder
    }
  }
}
#endif
