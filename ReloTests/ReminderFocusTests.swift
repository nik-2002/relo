import XCTest
@testable import Relo

private final class FakeReminderSource: ReminderSource, @unchecked Sendable {
  var accessState: ReminderAccessState
  var reminders: [FocusReminder]
  var completedIDs: [String] = []
  var completionError: Error?
  var lists: [ReminderList] = [
    ReminderList(id: "school", title: "School"),
    ReminderList(id: "home", title: "Home"),
  ]
  var defaultListID: String? = "home"
  var creationError: Error?
  private var nextID = 100

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

  func writableLists() -> [ReminderList] {
    lists
  }

  func createReminder(title: String, listID: String) throws -> FocusReminder {
    if let creationError { throw creationError }
    nextID += 1
    let list = lists.first { $0.id == listID }
    let reminder = FocusReminder(id: "\(nextID)", title: title, listTitle: list?.title ?? "")
    reminders.append(reminder)
    return reminder
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

  func testCompletingAnotherReminderFromThePickerKeepsTheLink() async {
    let source = FakeReminderSource(reminders: [essay, laundry])
    let store = ReminderFocusStore(source: source, defaults: defaults)
    await store.refresh()
    store.link(essay)

    XCTAssertTrue(store.complete(laundry))

    XCTAssertEqual(source.completedIDs, ["2"])
    XCTAssertEqual(store.reminders, [essay])
    XCTAssertEqual(store.linkedReminder, essay)
  }

  func testCompletingTheLinkedReminderFromThePickerClearsTheLink() async {
    let source = FakeReminderSource(reminders: [essay, laundry])
    let store = ReminderFocusStore(source: source, defaults: defaults)
    await store.refresh()
    store.link(essay)

    XCTAssertTrue(store.complete(essay))

    XCTAssertNil(store.linkedReminder)
    XCTAssertEqual(store.reminders, [laundry])
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

  func testNewRemindersGoToTheDefaultListUntilAnotherIsChosen() async {
    let source = FakeReminderSource()
    let store = ReminderFocusStore(source: source, defaults: defaults)
    await store.refresh()
    XCTAssertEqual(store.newReminderList?.title, "Home")

    store.chooseNewReminderList(source.lists[0])
    let relaunched = ReminderFocusStore(source: source, defaults: defaults)
    await relaunched.refresh()

    XCTAssertEqual(relaunched.newReminderList?.title, "School")
  }

  func testRememberedListThatWasDeletedFallsBackToTheDefault() async {
    let source = FakeReminderSource()
    defaults.set("gone", forKey: ReloSettingsKeys.newReminderList)
    let store = ReminderFocusStore(source: source, defaults: defaults)

    await store.refresh()

    XCTAssertEqual(store.newReminderListID, "home")
  }

  func testCreatingAReminderAddsItToTheChosenListAndLinksIt() async throws {
    let source = FakeReminderSource(reminders: [essay])
    let store = ReminderFocusStore(source: source, defaults: defaults)
    await store.refresh()
    store.chooseNewReminderList(source.lists[0])

    XCTAssertTrue(store.createAndLink(title: "  Read chapter 4 "))

    let linked = try XCTUnwrap(store.linkedReminder)
    XCTAssertEqual(linked.title, "Read chapter 4")
    XCTAssertEqual(linked.listTitle, "School")
    XCTAssertTrue(store.reminders.contains(linked))
    XCTAssertEqual(source.reminders.last, linked)
  }

  func testFailedCreationReportsAnErrorAndLinksNothing() async {
    struct Failure: Error {}
    let source = FakeReminderSource()
    source.creationError = Failure()
    let store = ReminderFocusStore(source: source, defaults: defaults)
    await store.refresh()

    XCTAssertFalse(store.createAndLink(title: "Read"))

    XCTAssertNil(store.linkedReminder)
    XCTAssertNotNil(store.completionError)
  }

  func testCreationIsOfferedOnlyForANewTitle() {
    let existing = [essay, FocusReminder(id: "3", title: "Café run", listTitle: "Home")]

    XCTAssertTrue(ReminderFocusStore.canCreate(from: "Write", existing: existing))
    XCTAssertFalse(ReminderFocusStore.canCreate(from: " write ESSAY ", existing: existing))
    XCTAssertFalse(ReminderFocusStore.canCreate(from: "cafe run", existing: existing))
    XCTAssertFalse(ReminderFocusStore.canCreate(from: "   ", existing: existing))
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

  func testSearchMatchesEveryWordInTitleOrListIgnoringCaseAndAccents() {
    let reminders = [
      FocusReminder(id: "1", title: "DJI drone batteries and bag", listTitle: "To Buy"),
      FocusReminder(id: "2", title: "Novena for Work", listTitle: "Interior Life"),
      FocusReminder(id: "3", title: "Café meeting", listTitle: "Inbox"),
    ]

    XCTAssertEqual(ReminderFocusStore.filter(reminders, matching: "bag drone").map(\.id), ["1"])
    XCTAssertEqual(ReminderFocusStore.filter(reminders, matching: "INTERIOR").map(\.id), ["2"])
    XCTAssertEqual(ReminderFocusStore.filter(reminders, matching: "cafe").map(\.id), ["3"])
    XCTAssertEqual(ReminderFocusStore.filter(reminders, matching: "  ").count, 3)
    XCTAssertTrue(ReminderFocusStore.filter(reminders, matching: "drone work").isEmpty)
  }

  func testGroupsCarryTheirListColor() {
    let red = ListColor(red: 1, green: 0.2, blue: 0.2)
    let groups = ReminderFocusStore.group([
      FocusReminder(id: "1", title: "A", listTitle: "Samar", listColor: red),
    ])
    XCTAssertEqual(groups.first?.listColor, red)
  }

  func testLinkSavedBeforeColorsAndTimesStillLoads() throws {
    let legacy = #"{"id":"1","title":"Write essay","listTitle":"School"}"#
    defaults.set(Data(legacy.utf8), forKey: ReloSettingsKeys.linkedReminder)

    let loaded = try XCTUnwrap(ReminderFocusStore.loadLinkedReminder(defaults: defaults))

    XCTAssertEqual(loaded.title, "Write essay")
    XCTAssertFalse(loaded.dueIncludesTime)
    XCTAssertNil(loaded.listColor)
  }

  func testDueLabelsFollowRemindersWording() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Manila"))
    let locale = Locale(identifier: "en_US")
    // Tuesday 3 November 2026, 10:30.
    let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 10, minute: 30)))

    func label(dayOffset: Int, hour: Int? = nil, years: Int = 0) throws -> ReminderDueLabel? {
      var day = try XCTUnwrap(calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: now)))
      day = try XCTUnwrap(calendar.date(byAdding: .year, value: years, to: day))
      let due = try XCTUnwrap(calendar.date(byAdding: .hour, value: hour ?? 0, to: day))
      let reminder = FocusReminder(
        id: "x", title: "x", listTitle: "x", dueDate: due, dueIncludesTime: hour != nil
      )
      return ReminderDueLabel.make(for: reminder, now: now, calendar: calendar, locale: locale)
    }

    XCTAssertEqual(try label(dayOffset: 0), ReminderDueLabel(text: "Today", isOverdue: false))
    // Foundation separates the time and "PM" with a narrow no-break space.
    XCTAssertEqual(
      try label(dayOffset: 0, hour: 14),
      ReminderDueLabel(text: "Today 2:00\u{202F}PM", isOverdue: false)
    )
    XCTAssertEqual(try label(dayOffset: 0, hour: 9)?.isOverdue, true)
    XCTAssertEqual(try label(dayOffset: 1)?.text, "Tomorrow")
    XCTAssertEqual(try label(dayOffset: -1), ReminderDueLabel(text: "Yesterday", isOverdue: true))
    XCTAssertEqual(try label(dayOffset: 2)?.text, "Thu")
    XCTAssertEqual(try label(dayOffset: 9)?.text, "Nov 12")
    XCTAssertEqual(try label(dayOffset: 0, years: 1)?.text, "Nov 3, 2027")

    let undated = FocusReminder(id: "y", title: "y", listTitle: "y")
    XCTAssertNil(ReminderDueLabel.make(for: undated, now: now, calendar: calendar, locale: locale))
  }

  func testPickerOpensBesideTheCardAndFlipsLeftNearTheScreenEdge() {
    let screen = NSRect(x: 0, y: 0, width: 1440, height: 875)
    let size = ReminderPickerPanel.contentSize
    let cardNearLeft = NSRect(x: 200, y: 600, width: 242, height: 140)
    let cardNearRight = NSRect(x: 1150, y: 600, width: 242, height: 140)

    let right = ReminderPickerPanelLayout.origin(primaryFrame: cardNearLeft, panelSize: size, availableFrame: screen)
    XCTAssertEqual(right.x, cardNearLeft.maxX + ReminderPickerPanelLayout.gap)
    XCTAssertEqual(right.y + size.height, cardNearLeft.maxY)

    let left = ReminderPickerPanelLayout.origin(primaryFrame: cardNearRight, panelSize: size, availableFrame: screen)
    XCTAssertEqual(left.x + size.width, cardNearRight.minX - ReminderPickerPanelLayout.gap)
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
