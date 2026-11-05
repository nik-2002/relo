import AppKit
import Combine
import EventKit

/// An open reminder a timer can be committed to. Identified by EventKit's
/// `calendarItemIdentifier`; the title is kept so the menu can show the linked
/// task before Reminders has been queried again.
nonisolated struct FocusReminder: Identifiable, Hashable, Codable, Sendable {
  let id: String
  var title: String
  var listTitle: String
  var dueDate: Date?
  /// False for all-day reminders, whose due date carries no meaningful time.
  var dueIncludesTime = false
  /// The Reminders list colour as sRGB components.
  var listColor: ListColor?

  init(
    id: String,
    title: String,
    listTitle: String,
    dueDate: Date? = nil,
    dueIncludesTime: Bool = false,
    listColor: ListColor? = nil
  ) {
    self.id = id
    self.title = title
    self.listTitle = listTitle
    self.dueDate = dueDate
    self.dueIncludesTime = dueIncludesTime
    self.listColor = listColor
  }

  // Links saved by 1.2 predate the colour and time fields.
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    title = try container.decode(String.self, forKey: .title)
    listTitle = try container.decode(String.self, forKey: .listTitle)
    dueDate = try container.decodeIfPresent(Date.self, forKey: .dueDate)
    dueIncludesTime = try container.decodeIfPresent(Bool.self, forKey: .dueIncludesTime) ?? false
    listColor = try container.decodeIfPresent(ListColor.self, forKey: .listColor)
  }
}

/// A Reminders list a new reminder can be added to.
nonisolated struct ReminderList: Identifiable, Hashable, Sendable {
  let id: String
  var title: String
  var color: ListColor?
}

nonisolated struct ListColor: Hashable, Codable, Sendable {
  var red: Double
  var green: Double
  var blue: Double

  init(red: Double, green: Double, blue: Double) {
    self.red = red
    self.green = green
    self.blue = blue
  }

  init?(_ color: NSColor?) {
    guard let srgb = color?.usingColorSpace(.sRGB) else { return nil }
    self.init(
      red: Double(srgb.redComponent),
      green: Double(srgb.greenComponent),
      blue: Double(srgb.blueComponent)
    )
  }
}

/// How a due date reads in the picker, following Reminders' own wording.
nonisolated struct ReminderDueLabel: Equatable, Sendable {
  let text: String
  let isOverdue: Bool

  static func make(
    for reminder: FocusReminder,
    now: Date = Date(),
    calendar: Calendar = .current,
    locale: Locale = .current
  ) -> ReminderDueLabel? {
    guard let due = reminder.dueDate else { return nil }

    let dayText: String
    if calendar.isDate(due, inSameDayAs: now) {
      dayText = "Today"
    } else if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
              calendar.isDate(due, inSameDayAs: tomorrow) {
      dayText = "Tomorrow"
    } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
              calendar.isDate(due, inSameDayAs: yesterday) {
      dayText = "Yesterday"
    } else if let days = calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: now),
                to: calendar.startOfDay(for: due)
              ).day,
              (2...6).contains(days) {
      dayText = due.formatted(Date.FormatStyle(locale: locale, calendar: calendar).weekday(.abbreviated))
    } else if calendar.component(.year, from: due) == calendar.component(.year, from: now) {
      dayText = due.formatted(
        Date.FormatStyle(locale: locale, calendar: calendar).month(.abbreviated).day()
      )
    } else {
      dayText = due.formatted(
        Date.FormatStyle(locale: locale, calendar: calendar).month(.abbreviated).day().year()
      )
    }

    let text: String
    if reminder.dueIncludesTime {
      let time = due.formatted(
        Date.FormatStyle(locale: locale, calendar: calendar).hour().minute()
      )
      text = "\(dayText) \(time)"
    } else {
      text = dayText
    }

    let isOverdue = reminder.dueIncludesTime
      ? due < now
      : calendar.startOfDay(for: due) < calendar.startOfDay(for: now)
    return ReminderDueLabel(text: text, isOverdue: isOverdue)
  }
}

nonisolated enum ReminderAccessState: Sendable {
  case notDetermined
  case granted
  case denied
}

nonisolated protocol ReminderSource: AnyObject, Sendable {
  var accessState: ReminderAccessState { get }
  func requestAccess() async -> ReminderAccessState
  func incompleteReminders() async -> [FocusReminder]
  /// Returns false when the reminder no longer exists.
  func markCompleted(id: String) throws -> Bool
  /// Lists that accept new reminders, in Reminders' order.
  func writableLists() -> [ReminderList]
  /// The list Reminders adds new reminders to by default.
  var defaultListID: String? { get }
  func createReminder(title: String, listID: String) throws -> FocusReminder
}

/// The EventKit-backed source. Kept nonisolated because EventKit delivers fetch
/// results on its own background queue.
nonisolated final class EventKitReminderSource: ReminderSource, @unchecked Sendable {
  let store = EKEventStore()

  var accessState: ReminderAccessState {
    switch EKEventStore.authorizationStatus(for: .reminder) {
    case .fullAccess:
      return .granted
    case .notDetermined:
      return .notDetermined
    default:
      return .denied
    }
  }

  func requestAccess() async -> ReminderAccessState {
    _ = try? await store.requestFullAccessToReminders()
    return accessState
  }

  func incompleteReminders() async -> [FocusReminder] {
    let predicate = store.predicateForIncompleteReminders(
      withDueDateStarting: nil,
      ending: nil,
      calendars: nil
    )
    return await withCheckedContinuation { continuation in
      store.fetchReminders(matching: predicate) { reminders in
        let items = (reminders ?? []).compactMap { reminder -> FocusReminder? in
          let title = (reminder.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
          guard !title.isEmpty else { return nil }
          // DateComponents.date is nil unless the components carry a calendar,
          // which EventKit does not guarantee.
          let components = reminder.dueDateComponents
          return FocusReminder(
            id: reminder.calendarItemIdentifier,
            title: title,
            listTitle: reminder.calendar?.title ?? "",
            dueDate: components.flatMap { Calendar.current.date(from: $0) },
            dueIncludesTime: components?.hour != nil,
            listColor: ListColor(reminder.calendar?.color)
          )
        }
        continuation.resume(returning: items)
      }
    }
  }

  func markCompleted(id: String) throws -> Bool {
    guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else {
      return false
    }
    reminder.isCompleted = true
    try store.save(reminder, commit: true)
    return true
  }

  func writableLists() -> [ReminderList] {
    store.calendars(for: .reminder)
      .filter(\.allowsContentModifications)
      .map { ReminderList(id: $0.calendarIdentifier, title: $0.title, color: ListColor($0.color)) }
  }

  var defaultListID: String? {
    store.defaultCalendarForNewReminders()?.calendarIdentifier
  }

  func createReminder(title: String, listID: String) throws -> FocusReminder {
    guard let calendar = store.calendar(withIdentifier: listID) else {
      throw CocoaError(.fileNoSuchFile)
    }
    let reminder = EKReminder(eventStore: store)
    reminder.title = title
    reminder.calendar = calendar
    try store.save(reminder, commit: true)
    return FocusReminder(
      id: reminder.calendarItemIdentifier,
      title: title,
      listTitle: calendar.title,
      listColor: ListColor(calendar.color)
    )
  }
}

nonisolated struct ReminderGroup: Identifiable, Equatable {
  var id: String { listTitle }
  let listTitle: String
  let listColor: ListColor?
  let reminders: [FocusReminder]
}

/// Holds the reminder the user has committed the timer to. Linking is optional:
/// with nothing linked Relo behaves exactly like a plain timer.
@MainActor
final class ReminderFocusStore: ObservableObject {
  static let maximumRemindersPerList = 40
  static let privacySettingsURL = URL(
    string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders"
  )!

  @Published private(set) var access: ReminderAccessState
  @Published private(set) var reminders: [FocusReminder] = []
  @Published private(set) var linkedReminder: FocusReminder?
  @Published private(set) var completionError: String?
  @Published private(set) var lists: [ReminderList] = []
  /// Where a reminder made from the picker goes: the last list used there,
  /// falling back to Reminders' default list.
  @Published private(set) var newReminderListID: String?

  private let source: any ReminderSource
  private let defaults: UserDefaults
  private var cancellables = Set<AnyCancellable>()

  init(
    source: any ReminderSource = EventKitReminderSource(),
    defaults: UserDefaults = .standard
  ) {
    self.source = source
    self.defaults = defaults
    access = source.accessState
    linkedReminder = Self.loadLinkedReminder(defaults: defaults)

    if let eventKitSource = source as? EventKitReminderSource {
      NotificationCenter.default.publisher(for: .EKEventStoreChanged, object: eventKitSource.store)
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in
          Task { await self?.refresh() }
        }
        .store(in: &cancellables)
    }
  }

  var groupedReminders: [ReminderGroup] {
    Self.group(reminders)
  }

  func groupedReminders(matching query: String) -> [ReminderGroup] {
    Self.group(Self.filter(reminders, matching: query))
  }

  func requestAccess() async {
    access = await source.requestAccess()
    await refresh()
  }

  func refresh() async {
    access = source.accessState
    guard access == .granted else {
      reminders = []
      lists = []
      return
    }
    reminders = await source.incompleteReminders()
    lists = source.writableLists()
    let saved = defaults.string(forKey: ReloSettingsKeys.newReminderList)
    newReminderListID = [saved, source.defaultListID]
      .compactMap { $0 }
      .first { id in lists.contains { $0.id == id } }
      ?? lists.first?.id
    // Completed or deleted in Reminders itself: the commitment is over.
    if let linkedReminder, !reminders.contains(where: { $0.id == linkedReminder.id }) {
      unlink()
    } else if let linkedReminder,
              let current = reminders.first(where: { $0.id == linkedReminder.id }),
              current != linkedReminder {
      link(current)
    }
  }

  func link(_ reminder: FocusReminder) {
    linkedReminder = reminder
    completionError = nil
    Self.saveLinkedReminder(reminder, defaults: defaults)
  }

  func unlink() {
    linkedReminder = nil
    completionError = nil
    Self.saveLinkedReminder(nil, defaults: defaults)
  }

  /// Ticks the linked reminder off in Reminders and clears the link.
  @discardableResult
  func completeLinkedReminder() -> Bool {
    guard let linkedReminder else { return false }
    return complete(linkedReminder)
  }

  /// Ticks a reminder off in Reminders. Completing the linked reminder also
  /// clears the link, since the commitment is fulfilled.
  @discardableResult
  func complete(_ reminder: FocusReminder) -> Bool {
    do {
      _ = try source.markCompleted(id: reminder.id)
      reminders.removeAll { $0.id == reminder.id }
      completionError = nil
      if linkedReminder?.id == reminder.id {
        unlink()
      }
      return true
    } catch {
      completionError = "Couldn't update Reminders."
      return false
    }
  }

  var newReminderList: ReminderList? {
    lists.first { $0.id == newReminderListID }
  }

  func chooseNewReminderList(_ list: ReminderList) {
    newReminderListID = list.id
    defaults.set(list.id, forKey: ReloSettingsKeys.newReminderList)
  }

  /// Adds a reminder to the chosen list and commits the timer to it.
  @discardableResult
  func createAndLink(title: String) -> Bool {
    let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty, let listID = newReminderListID else { return false }
    do {
      let reminder = try source.createReminder(title: title, listID: listID)
      reminders.append(reminder)
      defaults.set(listID, forKey: ReloSettingsKeys.newReminderList)
      link(reminder)
      return true
    } catch {
      completionError = "Couldn't add to Reminders."
      return false
    }
  }

  /// The picker offers to add a reminder unless the query already names one.
  static func canCreate(from query: String, existing reminders: [FocusReminder]) -> Bool {
    let title = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty else { return false }
    return !reminders.contains {
      $0.title.compare(title, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }
  }

  func openPrivacySettings() {
    NSWorkspace.shared.open(Self.privacySettingsURL)
  }

  /// Lists keep the order Reminders returns them in; within a list, reminders
  /// with the soonest due date come first and undated ones follow by title.
  static func group(_ reminders: [FocusReminder]) -> [ReminderGroup] {
    var listOrder: [String] = []
    var byList: [String: [FocusReminder]] = [:]
    for reminder in reminders {
      if byList[reminder.listTitle] == nil {
        listOrder.append(reminder.listTitle)
      }
      byList[reminder.listTitle, default: []].append(reminder)
    }
    return listOrder.map { list in
      let sorted = (byList[list] ?? []).sorted { lhs, rhs in
        switch (lhs.dueDate, rhs.dueDate) {
        case let (left?, right?) where left != right:
          return left < right
        case (.some, .none):
          return true
        case (.none, .some):
          return false
        default:
          return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
      }
      return ReminderGroup(
        listTitle: list,
        listColor: sorted.first?.listColor,
        reminders: Array(sorted.prefix(maximumRemindersPerList))
      )
    }
  }

  /// Every word of the query must appear in the title or the list name,
  /// ignoring case and diacritics, so "drone bag" finds "DJI drone batteries and bag".
  static func filter(_ reminders: [FocusReminder], matching query: String) -> [FocusReminder] {
    let words = query
      .split(whereSeparator: \.isWhitespace)
      .map(String.init)
    guard !words.isEmpty else { return reminders }
    return reminders.filter { reminder in
      let haystack = "\(reminder.title) \(reminder.listTitle)"
      return words.allSatisfy {
        haystack.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil
      }
    }
  }

  static func loadLinkedReminder(defaults: UserDefaults) -> FocusReminder? {
    guard let data = defaults.data(forKey: ReloSettingsKeys.linkedReminder) else { return nil }
    return try? JSONDecoder().decode(FocusReminder.self, from: data)
  }

  private static func saveLinkedReminder(_ reminder: FocusReminder?, defaults: UserDefaults) {
    guard let reminder, let data = try? JSONEncoder().encode(reminder) else {
      defaults.removeObject(forKey: ReloSettingsKeys.linkedReminder)
      return
    }
    defaults.set(data, forKey: ReloSettingsKeys.linkedReminder)
  }
}
