import Foundation

struct ReloTimerParser {
  let defaultUnit: DefaultTimeUnit
  var calendar: Calendar = .current

  func duration(from input: String) -> TimeInterval {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !trimmed.isEmpty else { return 0 }

    if let interval = colonDuration(from: trimmed) {
      return interval
    }

    if let composite = compositeDuration(from: trimmed) {
      return composite
    }

    let numberCharacters = "0123456789."
    let numberPart = trimmed.prefix { numberCharacters.contains($0) }
    let unitPart = trimmed.dropFirst(numberPart.count)
      .trimmingCharacters(in: .whitespacesAndNewlines)

    let value = Double(numberPart) ?? 0
    guard value > 0 else { return 0 }

    let multiplier: Double
    if unitPart.isEmpty {
      multiplier = defaultUnit.multiplier
    } else {
      guard let parsedUnit = unit(for: unitPart) else { return 0 }
      multiplier = parsedUnit.multiplier
    }

    return max(0, value * multiplier)
  }

  func timeOfDayInterval(from input: String, now: Date = Date()) -> TimeInterval? {
    var compact = input.replacingOccurrences(of: " ", with: "")
    compact = compact.replacingOccurrences(of: ".", with: "")
    if compact == "noon" {
      return intervalUntil(hour: 12, minute: 0, now: now)
    }
    if compact == "midnight" {
      return intervalUntil(hour: 0, minute: 0, now: now)
    }

    if compact.hasSuffix("a") {
      compact.removeLast()
      compact += "am"
    } else if compact.hasSuffix("p") {
      compact.removeLast()
      compact += "pm"
    }

    // Time-of-day input must carry an am/pm marker. Bare colon times like
    // "18:00" or "6:15" are intentionally treated as MM:SS / HH:MM:SS
    // durations by `duration(from:)`, so there is no unambiguous room for a
    // 24-hour clock syntax here.
    guard compact.contains("am") || compact.contains("pm") else {
      return nil
    }

    if !compact.contains(":") {
      let suffix = compact.suffix(2)
      let prefix = compact.dropLast(2)
      if (suffix == "am" || suffix == "pm"), prefix.count >= 3,
         prefix.allSatisfy({ $0.isNumber }) {
        let minutes = prefix.suffix(2)
        let hours = prefix.dropLast(2)
        compact = "\(hours):\(minutes)\(suffix)"
      }
    }

    // Only 12-hour formats are reachable: the guard above requires an am/pm
    // marker, which the 24-hour patterns would never match.
    let formats = ["h:mma", "ha"]
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = calendar.timeZone

    for format in formats {
      formatter.dateFormat = format
      guard let parsed = formatter.date(from: compact) else { continue }
      let components = calendar.dateComponents([.hour, .minute], from: parsed)
      guard let hour = components.hour, let minute = components.minute else { continue }
      if let interval = intervalUntil(hour: hour, minute: minute, now: now) {
        return interval
      }
    }

    return nil
  }

  private func compositeDuration(from input: String) -> TimeInterval? {
    let cleaned = input.replacingOccurrences(of: ",", with: "")
    let scanner = Scanner(string: cleaned)
    scanner.charactersToBeSkipped = .whitespacesAndNewlines

    var total: Double = 0
    var lastUnit: ParsedUnit?

    while !scanner.isAtEnd {
      guard let value = scanner.scanDouble(), value > 0 else { return nil }

      let unitToken = scanner.scanCharacters(from: .letters)?.lowercased()
      if let unitToken, !unitToken.isEmpty {
        guard let parsedUnit = unit(for: unitToken) else { return nil }
        total += value * parsedUnit.multiplier
        lastUnit = parsedUnit
      } else {
        guard let currentUnit = lastUnit,
              let nextUnit = nextSmallerUnit(after: currentUnit) else {
          return nil
        }
        total += value * nextUnit.multiplier
        lastUnit = nextUnit
      }
    }

    return total > 0 ? total : nil
  }

  private func colonDuration(from input: String) -> TimeInterval? {
    guard input.contains(":") else { return nil }
    let compact = input.replacingOccurrences(of: " ", with: "")
    guard !compact.contains("am"), !compact.contains("pm") else { return nil }

    let parts = compact.split(separator: ":", omittingEmptySubsequences: false)
    guard parts.count == 2 || parts.count == 3 else { return nil }
    let firstPart = String(parts[0])
    let secondPart = String(parts[1])
    let first: Int
    if firstPart.isEmpty, compact.hasPrefix(":") {
      first = 0
    } else if let parsed = Int(firstPart) {
      first = parsed
    } else {
      return nil
    }
    guard let second = Int(secondPart), first >= 0, second >= 0 else { return nil }

    if parts.count == 2 {
      guard second < 60 else { return nil }
      return Double(first * 60 + second)
    }

    guard let third = Int(parts[2]), third >= 0, second < 60, third < 60 else { return nil }
    return Double(first * 3600 + second * 60 + third)
  }

  private enum ParsedUnit {
    case hour
    case minute
    case second

    var multiplier: Double {
      switch self {
      case .hour:
        return 3600
      case .minute:
        return 60
      case .second:
        return 1
      }
    }
  }

  private func unit(for token: String) -> ParsedUnit? {
    switch token {
    case "m", "min", "mins", "minute", "minutes":
      return .minute
    case "s", "sec", "secs", "second", "seconds":
      return .second
    case "h", "hr", "hrs", "hour", "hours":
      return .hour
    default:
      return nil
    }
  }

  private func nextSmallerUnit(after unit: ParsedUnit) -> ParsedUnit? {
    switch unit {
    case .hour:
      return .minute
    case .minute:
      return .second
    case .second:
      return nil
    }
  }

  private func intervalUntil(hour: Int, minute: Int, now: Date) -> TimeInterval? {
    guard var target = calendar.date(
      bySettingHour: hour,
      minute: minute,
      second: 0,
      of: now
    ) else {
      return nil
    }
    if target <= now {
      guard let next = calendar.date(byAdding: .day, value: 1, to: target) else { return nil }
      target = next
    }
    let interval = target.timeIntervalSince(now)
    return interval > 0 ? interval : nil
  }
}
