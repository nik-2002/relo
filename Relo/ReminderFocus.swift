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
          return FocusReminder(
            id: reminder.calendarItemIdentifier,
            title: title,
            listTitle: reminder.calendar?.title ?? "",
            dueDate: reminder.dueDateComponents?.date
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
}

nonisolated struct ReminderGroup: Identifiable, Equatable {
  var id: String { listTitle }
  let listTitle: String
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

  func requestAccess() async {
    access = await source.requestAccess()
    await refresh()
  }

  func refresh() async {
    access = source.accessState
    guard access == .granted else {
      reminders = []
      return
    }
    reminders = await source.incompleteReminders()
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
    do {
      _ = try source.markCompleted(id: linkedReminder.id)
      reminders.removeAll { $0.id == linkedReminder.id }
      unlink()
      return true
    } catch {
      completionError = "Couldn't update Reminders."
      return false
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
        reminders: Array(sorted.prefix(maximumRemindersPerList))
      )
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
