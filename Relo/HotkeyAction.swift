import Carbon
import Foundation

enum HotkeyAction: CaseIterable, Hashable {
  case open
  case pauseResume
  case clear

  var id: UInt32 {
    switch self {
    case .open:
      return 1
    case .pauseResume:
      return 2
    case .clear:
      return 3
    }
  }

  var userDefaultsKey: String {
    switch self {
    case .open:
      return ReloSettingsKeys.openHotkey
    case .pauseResume:
      return ReloSettingsKeys.pauseResumeHotkey
    case .clear:
      return ReloSettingsKeys.clearHotkey
    }
  }

  var defaultHotkey: Hotkey {
    let modifiers = UInt32(controlKey | optionKey | cmdKey)
    switch self {
    case .open:
      return Hotkey(keyCode: UInt16(kVK_ANSI_R), modifiers: modifiers)
    case .pauseResume:
      return Hotkey(keyCode: UInt16(kVK_ANSI_P), modifiers: modifiers)
    case .clear:
      return Hotkey(keyCode: UInt16(kVK_ANSI_X), modifiers: modifiers)
    }
  }

  init?(id: UInt32) {
    switch id {
    case HotkeyAction.open.id:
      self = .open
    case HotkeyAction.pauseResume.id:
      self = .pauseResume
    case HotkeyAction.clear.id:
      self = .clear
    default:
      return nil
    }
  }
}
