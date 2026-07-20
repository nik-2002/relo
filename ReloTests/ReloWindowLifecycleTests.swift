import AppKit
import XCTest
@testable import Relo

final class MenuPanelLayoutTests: XCTestCase {
  func testColdStartSizeIsImmediatelyUsable() {
    XCTAssertEqual(MenuPanelLayout.defaultContentSize.width, 210)
    XCTAssertEqual(MenuPanelLayout.defaultContentSize.height, 152)
    XCTAssertGreaterThan(MenuPanelLayout.defaultContentSize.width, 0)
    XCTAssertGreaterThan(MenuPanelLayout.defaultContentSize.height, 0)
  }

  func testPanelIsCenteredBelowItsMenuBarAnchor() {
    let origin = MenuPanelLayout.origin(
      anchorFrame: NSRect(x: 500, y: 740, width: 30, height: 24),
      panelSize: NSSize(width: 210, height: 152),
      availableFrame: NSRect(x: 0, y: 0, width: 1_200, height: 740)
    )

    XCTAssertEqual(origin.x, 410)
    XCTAssertEqual(origin.y, 582)
  }

  func testPanelStaysInsideLeftAndRightScreenEdges() {
    let availableFrame = NSRect(x: 100, y: 50, width: 900, height: 700)
    let panelSize = NSSize(width: 210, height: 152)

    let leftOrigin = MenuPanelLayout.origin(
      anchorFrame: NSRect(x: 100, y: 730, width: 20, height: 20),
      panelSize: panelSize,
      availableFrame: availableFrame
    )
    let rightOrigin = MenuPanelLayout.origin(
      anchorFrame: NSRect(x: 980, y: 730, width: 20, height: 20),
      panelSize: panelSize,
      availableFrame: availableFrame
    )

    XCTAssertEqual(leftOrigin.x, 108)
    XCTAssertEqual(rightOrigin.x, 782)
  }

  func testPanelStaysAboveBottomScreenMargin() {
    let origin = MenuPanelLayout.origin(
      anchorFrame: NSRect(x: 300, y: 80, width: 20, height: 20),
      panelSize: NSSize(width: 210, height: 152),
      availableFrame: NSRect(x: 0, y: 50, width: 900, height: 700)
    )

    XCTAssertEqual(origin.y, 58)
  }

  func testColdStartAnchorRetryHasAStableLimit() {
    XCTAssertEqual(MenuPanelLayout.nextAnchorRetry(after: 0), 1)
    XCTAssertEqual(MenuPanelLayout.nextAnchorRetry(after: 1), 2)
    XCTAssertEqual(MenuPanelLayout.nextAnchorRetry(after: 2), 3)
    XCTAssertNil(MenuPanelLayout.nextAnchorRetry(after: 3))
    XCTAssertNil(MenuPanelLayout.nextAnchorRetry(after: 10))
  }

  func testColdStartReanchoringIsFrequentAndBounded() throws {
    let delays = MenuPanelLayout.reanchorDelays

    XCTAssertEqual(delays, delays.sorted())
    XCTAssertGreaterThanOrEqual(delays.count, 5)
    XCTAssertLessThanOrEqual(try XCTUnwrap(delays.first), 0.1)
    XCTAssertLessThanOrEqual(try XCTUnwrap(delays.last), 2.0)
  }
}

@MainActor
final class MenuPanelTests: XCTestCase {
  func testPanelStartsAtAVisibleSizeAndCanBecomeKey() {
    let panel = MenuPanel()

    XCTAssertEqual(panel.contentRect(forFrameRect: panel.frame).size, MenuPanelLayout.defaultContentSize)
    XCTAssertTrue(panel.canBecomeKey)
    XCTAssertFalse(panel.canBecomeMain)
    XCTAssertFalse(panel.isReleasedWhenClosed)
    XCTAssertEqual(panel.level, .popUpMenu)
    XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
  }

  func testUnattachedStatusButtonFailsWithoutShowingAZeroSizedPanel() {
    let panel = MenuPanel()
    let button = NSStatusBarButton(frame: NSRect(x: 0, y: 0, width: 24, height: 24))

    XCTAssertFalse(panel.show(relativeTo: button))
    XCTAssertFalse(panel.isShown)
    XCTAssertEqual(panel.frame.size, MenuPanelLayout.defaultContentSize)
  }

  func testSettingsCanOpenAfterDismissingAnEditingPanel() throws {
    _ = NSApplication.shared
    let panel = MenuPanel()
    let settingsController = SettingsWindowController(activatesApplication: false)
    let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 120, height: 24))
    panel.contentView = NSView(frame: NSRect(origin: .zero, size: MenuPanelLayout.defaultContentSize))
    panel.contentView?.addSubview(textField)
    panel.makeKeyAndOrderFront(nil)
    defer {
      panel.orderOut(nil)
      settingsController.window?.close()
    }

    XCTAssertTrue(panel.makeFirstResponder(textField))
    let editingResponder = try XCTUnwrap(panel.firstResponder)

    panel.dismiss()

    XCTAssertFalse(panel.firstResponder === editingResponder)
    XCTAssertTrue(panel.firstResponder === panel)
    XCTAssertFalse(panel.isShown)

    settingsController.show()
    XCTAssertTrue(try XCTUnwrap(settingsController.window).isVisible)
  }
}

@MainActor
final class SettingsPresentationCoordinatorTests: XCTestCase {
  func testSettingsAreScheduledOnlyAfterTheMenuIsDismissed() {
    var events: [String] = []
    var scheduledAction: SettingsPresentationCoordinator.Action?

    SettingsPresentationCoordinator.present(
      dismissMenu: { events.append("dismiss") },
      showSettings: { events.append("show") },
      schedule: { action in
        events.append("schedule")
        scheduledAction = action
      }
    )

    XCTAssertEqual(events, ["dismiss", "schedule"])
    XCTAssertNotNil(scheduledAction)
    scheduledAction?()
    XCTAssertEqual(events, ["dismiss", "schedule", "show"])
  }

  func testSettingsAreNeverShownSynchronouslyDuringDismissal() {
    var menuIsDismissed = false
    var scheduledAction: SettingsPresentationCoordinator.Action?

    SettingsPresentationCoordinator.present(
      dismissMenu: { menuIsDismissed = true },
      showSettings: { XCTAssertTrue(menuIsDismissed) },
      schedule: { scheduledAction = $0 }
    )

    XCTAssertTrue(menuIsDismissed)
    scheduledAction?()
  }
}

@MainActor
final class SettingsWindowControllerTests: XCTestCase {
  func testSettingsWindowKeepsCloseEnabledAndDisablesMinimizeAndZoom() throws {
    _ = NSApplication.shared
    let controller = SettingsWindowController(activatesApplication: false)
    controller.show()
    let window = try XCTUnwrap(controller.window)
    defer { window.close() }

    XCTAssertTrue(window.styleMask.contains(.closable))
    XCTAssertTrue(window.styleMask.contains(.miniaturizable))
    XCTAssertTrue(window.styleMask.contains(.resizable))
    XCTAssertTrue(try XCTUnwrap(window.standardWindowButton(.closeButton)).isEnabled)
    XCTAssertFalse(try XCTUnwrap(window.standardWindowButton(.miniaturizeButton)).isEnabled)
    XCTAssertFalse(try XCTUnwrap(window.standardWindowButton(.zoomButton)).isEnabled)
  }

  func testClosingSettingsDiscardsTheWindowBeforeReopening() throws {
    _ = NSApplication.shared
    let controller = SettingsWindowController(activatesApplication: false)
    controller.show()
    let firstWindow = try XCTUnwrap(controller.window)
    XCTAssertTrue(firstWindow.isVisible)

    firstWindow.close()
    XCTAssertFalse(firstWindow.isVisible)
    XCTAssertNil(controller.window)

    controller.show()
    let reopenedWindow = try XCTUnwrap(controller.window)
    XCTAssertFalse(firstWindow === reopenedWindow)
    XCTAssertTrue(reopenedWindow.isVisible)
    reopenedWindow.close()
  }

  func testSettingsCanRepeatedlyCloseAndReopenAfterEditingAField() throws {
    _ = NSApplication.shared
    let controller = SettingsWindowController(activatesApplication: false)
    var previousWindow: NSWindow?

    for _ in 0..<3 {
      controller.show()
      let window = try XCTUnwrap(controller.window)
      XCTAssertFalse(window === previousWindow)

      window.contentView?.layoutSubtreeIfNeeded()
      let textField = try XCTUnwrap(firstEditableTextField(in: window.contentView))
      XCTAssertTrue(window.makeFirstResponder(textField))

      previousWindow = window
      window.close()
      XCTAssertNil(controller.window)
    }
  }

  private func firstEditableTextField(in view: NSView?) -> NSTextField? {
    guard let view else { return nil }
    if let textField = view as? NSTextField, textField.isEditable {
      return textField
    }
    for subview in view.subviews {
      if let match = firstEditableTextField(in: subview) {
        return match
      }
    }
    return nil
  }
}

final class HotkeyConfigurationTests: XCTestCase {
  func testActionIdentifiersAreUniqueAndRoundTrip() {
    let identifiers = HotkeyAction.allCases.map(\.id)

    XCTAssertEqual(Set(identifiers).count, HotkeyAction.allCases.count)
    for action in HotkeyAction.allCases {
      XCTAssertEqual(HotkeyAction(id: action.id), action)
    }
    XCTAssertNil(HotkeyAction(id: 999))
  }

  func testDefaultHotkeysAreUniqueAndUseValidModifiers() {
    let hotkeys = HotkeyAction.allCases.map(\.defaultHotkey)

    XCTAssertEqual(Set(hotkeys.map { "\($0.keyCode)-\($0.modifiers)" }).count, hotkeys.count)
    for hotkey in hotkeys {
      XCTAssertTrue(Hotkey.isValid(modifierFlags: hotkey.modifierFlags))
    }
  }

  func testUnsafeModifierOnlyShortcutsAreRejected() {
    XCTAssertFalse(Hotkey.isValid(modifierFlags: []))
    XCTAssertFalse(Hotkey.isValid(modifierFlags: [.shift]))
    XCTAssertFalse(Hotkey.isValid(modifierFlags: [.function]))
    XCTAssertTrue(Hotkey.isValid(modifierFlags: [.command]))
    XCTAssertTrue(Hotkey.isValid(modifierFlags: [.control, .option]))
  }
}
