import XCTest
@testable import Relo

private final class FakeReminderSource: ReminderSource, @unchecked Sendable {
  var accessState: ReminderAccessState
  var reminders: [FocusReminder]
  var completedIDs: [String] = []
  var completionError: Error?

  init(access: ReminderAccessState = .granted, reminders: [FocusReminder] = []) {
    accessState = access
    self.reminders = reminders
  }

  func requestAccess() async -> ReminderAccessState {
    if accessState == .notDetermined {
      accessState = .granted
    }
    return accessState
  }

  func incompleteReminders() async -> [FocusReminder] {
    reminders
  }

  func markCompleted(id: String) throws -> Bool {
    if let completionError { throw completionError }
    completedIDs.append(id)
    reminders.removeAll { $0.id == id }
    return true
  }
}

@MainActor
final class ReminderFocusStoreTests: XCTestCase {
  private var defaults: UserDefaults!
  private let suiteName = "ReloTests.ReminderFocus"

  private let essay = FocusReminder(id: "1", title: "Write essay", listTitle: "School")
  private let laundry = FocusReminder(id: "2", title: "Laundry", listTitle: "Home")

  override func setUp() async throws {
    try await super.setUp()
    defaults = UserDefaults(suiteName: suiteName)
    defaults.removePersistentDomain(forName: suiteName)
  }

  override func tearDown() async throws {
    defaults.removePersistentDomain(forName: suiteName)
    defaults = nil
    try await super.tearDown()
  }

  func testLinkedReminderIsRememberedAcrossLaunches() {
    let source = FakeReminderSource(reminders: [essay])
    ReminderFocusStore(source: source, defaults: defaults).link(essay)

    let relaunched = ReminderFocusStore(source: source, defaults: defaults)

    XCTAssertEqual(relaunched.linkedReminder, essay)
  }

  func testDoneCompletesTheReminderAndClearsTheLink() {
    let source = FakeReminderSource(reminders: [essay, laundry])
    let store = ReminderFocusStore(source: source, defaults: defaults)
    store.link(essay)

    XCTAssertTrue(store.completeLinkedReminder())

    XCTAssertEqual(source.completedIDs, ["1"])
    XCTAssertNil(store.linkedReminder)
    XCTAssertNil(ReminderFocusStore.loadLinkedReminder(defaults: defaults))
  }

  func testFailedCompletionKeepsTheLinkAndReportsAnError() {
    struct Failure: Error {}
    let source = FakeReminderSource(reminders: [essay])
    source.completionError = Failure()
    let store = ReminderFocusStore(source: source, defaults: defaults)
    store.link(essay)

    XCTAssertFalse(store.completeLinkedReminder())

    XCTAssertEqual(store.linkedReminder, essay)
    XCTAssertNotNil(store.completionError)
  }

  func testReminderCompletedElsewhereIsUnlinkedOnRefresh() async {
    let source = FakeReminderSource(reminders: [essay, laundry])
    let store = ReminderFocusStore(source: source, defaults: defaults)
    store.link(essay)

    source.reminders = [laundry]
    await store.refresh()

    XCTAssertNil(store.linkedReminder)
  }

  func testRenamedReminderUpdatesTheLinkedTitle() async {
    let source = FakeReminderSource(reminders: [essay])
    let store = ReminderFocusStore(source: source, defaults: defaults)
    store.link(essay)

    source.reminders = [FocusReminder(id: "1", title: "Write history essay", listTitle: "School")]
    await store.refresh()

    XCTAssertEqual(store.linkedReminder?.title, "Write history essay")
  }

  func testWithoutAccessNoRemindersAreListedAndRequestingLoadsThem() async {
    let source = FakeReminderSource(access: .notDetermined, reminders: [essay])
    let store = ReminderFocusStore(source: source, defaults: defaults)

    await store.refresh()
    XCTAssertEqual(store.access, .notDetermined)
    XCTAssertTrue(store.reminders.isEmpty)

    await store.requestAccess()
    XCTAssertEqual(store.access, .granted)
    XCTAssertEqual(store.reminders, [essay])
  }

  func testGroupsKeepListOrderAndSortByDueDateThenTitle() {
    let now = Date()
    let reminders = [
      FocusReminder(id: "a", title: "Zebra", listTitle: "Home"),
      FocusReminder(id: "b", title: "Later", listTitle: "Work", dueDate: now.addingTimeInterval(3_600)),
      FocusReminder(id: "c", title: "Apple", listTitle: "Home"),
      FocusReminder(id: "d", title: "Soon", listTitle: "Work", dueDate: now),
      FocusReminder(id: "e", title: "Undated", listTitle: "Work"),
    ]

    let groups = ReminderFocusStore.group(reminders)

    XCTAssertEqual(groups.map(\.listTitle), ["Home", "Work"])
    XCTAssertEqual(groups[0].reminders.map(\.title), ["Apple", "Zebra"])
    XCTAssertEqual(groups[1].reminders.map(\.title), ["Soon", "Later", "Undated"])
  }

  func testFloatingWindowGrowsOnlyWhenAReminderIsLinked() {
    XCTAssertEqual(
      FloatingCountdownWindowController.contentSize(hasLinkedReminder: false),
      FloatingCountdownWindowController.contentSize
    )
    XCTAssertGreaterThan(
      FloatingCountdownWindowController.contentSize(hasLinkedReminder: true).height,
      FloatingCountdownWindowController.contentSize.height
    )
  }
}
