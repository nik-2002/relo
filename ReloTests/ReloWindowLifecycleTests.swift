import AppKit
import XCTest
@testable import Relo

final class MenuPanelLayoutTests: XCTestCase {
  func testGeometryUsesRoleBasedMacOSShapes() {
    XCTAssertEqual(ReloGeometry.menuSurfaceRadius, 14)
    XCTAssertEqual(ReloGeometry.compactControlRadius, 6)
    XCTAssertEqual(ReloGeometry.floatingSurfaceRadius, 15)
    XCTAssertEqual(ReloGeometry.menuBarTimerRadius, 7)
    XCTAssertEqual(ReloGeometry.capsuleRadius(forHeight: 30), 15)
  }

  func testColdStartSizeIsImmediatelyUsable() {
    XCTAssertEqual(MenuPanelLayout.defaultContentSize.width, 242)
    XCTAssertEqual(MenuPanelLayout.defaultContentSize.height, 120)
    XCTAssertGreaterThan(MenuPanelLayout.defaultContentSize.width, 0)
    XCTAssertGreaterThan(MenuPanelLayout.defaultContentSize.height, 0)
  }

  func testPanelTopLeftIsAlignedBelowItsMenuBarAnchor() {
    let origin = MenuPanelLayout.origin(
      anchorFrame: NSRect(x: 500, y: 740, width: 30, height: 24),
      panelSize: NSSize(width: 242, height: 120),
      availableFrame: NSRect(x: 0, y: 0, width: 1_200, height: 740)
    )

    XCTAssertEqual(origin.x, 500)
    XCTAssertEqual(origin.y, 614)
  }

  func testPanelStaysInsideLeftAndRightScreenEdges() {
    let availableFrame = NSRect(x: 100, y: 50, width: 900, height: 700)
    let panelSize = NSSize(width: 242, height: 152)

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
    XCTAssertEqual(rightOrigin.x, 750)
  }

  func testPanelStaysAboveBottomScreenMargin() {
    let origin = MenuPanelLayout.origin(
      anchorFrame: NSRect(x: 300, y: 80, width: 20, height: 20),
      panelSize: NSSize(width: 242, height: 152),
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

  func testSecondaryPanelHasAnIndependentFixedSize() {
    let primaryPanel = MenuPanel()
    let secondaryPanel = SecondaryMenuPanel()

    XCTAssertEqual(primaryPanel.frame.size, MenuPanelLayout.defaultContentSize)
    XCTAssertEqual(secondaryPanel.frame.size, SecondaryMenuPanel.contentSize)
    XCTAssertNotEqual(secondaryPanel.frame.size, primaryPanel.frame.size)
    XCTAssertEqual(secondaryPanel.animationBehavior, .none)
  }

  func testSecondaryPanelTucksUnderEllipsisWithOnlyItsFirstRowOverlapping() {
    let primaryFrame = NSRect(x: 500, y: 600, width: 242, height: 140)
    let origin = SecondaryMenuPanelLayout.origin(
      primaryFrame: primaryFrame,
      panelSize: SecondaryMenuPanel.contentSize,
      availableFrame: NSRect(x: 0, y: 0, width: 1_440, height: 900)
    )

    XCTAssertEqual(origin.x, 692)
    XCTAssertEqual(origin.y, 492)
    XCTAssertEqual(
      origin.x + SecondaryMenuPanelLayout.secondaryContentLeadingInset,
      primaryFrame.maxX - SecondaryMenuPanelLayout.primaryTrailingPadding
        - SecondaryMenuPanelLayout.ellipsisButtonSize
    )
    XCTAssertEqual(
      origin.y + SecondaryMenuPanel.contentSize.height,
      primaryFrame.minY + SecondaryMenuPanelLayout.actionRowOverlap
    )
  }

  func testSecondaryPanelStaysOnScreenNearTheRightEdge() {
    let primaryFrame = NSRect(x: 1_180, y: 600, width: 242, height: 140)
    let origin = SecondaryMenuPanelLayout.origin(
      primaryFrame: primaryFrame,
      panelSize: SecondaryMenuPanel.contentSize,
      availableFrame: NSRect(x: 0, y: 0, width: 1_440, height: 900)
    )

    XCTAssertEqual(origin.x, 1_276)
  }

  func testFloatingDisplayStaysVisibleRegardlessOfTimerState() {
    XCTAssertTrue(FloatingCountdownWindowController.shouldShow(
      isDisplayEnabled: true,
      isDismissed: false
    ))
    XCTAssertFalse(FloatingCountdownWindowController.shouldShow(
      isDisplayEnabled: false,
      isDismissed: false
    ))
    XCTAssertFalse(FloatingCountdownWindowController.shouldShow(
      isDisplayEnabled: true,
      isDismissed: true
    ))
  }

  func testFloatingDisplayDismissalLiftsOnTheNextTimerOrReEnable() {
    // A timer starting lifts a dismissal.
    XCTAssertTrue(FloatingCountdownWindowController.shouldClearDismissal(
      hasActiveTimer: true,
      hadActiveTimer: false,
      isDisplayEnabled: true,
      wasDisplayEnabled: true
    ))
    // Re-enabling the display lifts a dismissal on its own.
    XCTAssertTrue(FloatingCountdownWindowController.shouldClearDismissal(
      hasActiveTimer: false,
      hadActiveTimer: false,
      isDisplayEnabled: true,
      wasDisplayEnabled: false
    ))
    // A countdown reaching zero is not a start, so the dismissal holds.
    XCTAssertFalse(FloatingCountdownWindowController.shouldClearDismissal(
      hasActiveTimer: false,
      hadActiveTimer: true,
      isDisplayEnabled: true,
      wasDisplayEnabled: true
    ))
    // Nor is a timer that was already running.
    XCTAssertFalse(FloatingCountdownWindowController.shouldClearDismissal(
      hasActiveTimer: true,
      hadActiveTimer: true,
      isDisplayEnabled: true,
      wasDisplayEnabled: true
    ))
  }

  func testFloatingDisplayPreferenceChangesAfterSecondaryPanelHandoff() {
    var events: [String] = []
    var scheduledAction: FloatingDisplayMenuCoordinator.Action?

    FloatingDisplayMenuCoordinator.setEnabled(
      true,
      dismissSecondary: { events.append("dismiss") },
      restorePrimaryKey: { events.append("restore-key") },
      writePreference: { events.append("write:\($0)") },
      schedule: { action in
        events.append("schedule")
        scheduledAction = action
      }
    )

    XCTAssertEqual(events, ["dismiss", "restore-key", "schedule"])
    scheduledAction?()
    XCTAssertEqual(events, ["dismiss", "restore-key", "schedule", "write:true"])
  }

  func testFloatingDisplayPreferenceCanBeDisabledThroughSameHandoff() {
    var writtenValue: Bool?

    FloatingDisplayMenuCoordinator.setEnabled(
      false,
      dismissSecondary: {},
      restorePrimaryKey: {},
      writePreference: { writtenValue = $0 },
      schedule: { $0() }
    )

    XCTAssertEqual(writtenValue, false)
    XCTAssertFalse(FloatingCountdownWindowController.shouldShow(
      isDisplayEnabled: false,
      isDismissed: false
    ))
  }

  func testFloatingDisplayDefaultsToUpperRightOfVisibleScreen() {
    let origin = FloatingCountdownWindowController.defaultOrigin(
      contentSize: NSSize(width: 110, height: 48),
      visibleFrame: NSRect(x: 0, y: 24, width: 1_440, height: 876)
    )

    XCTAssertEqual(origin, NSPoint(x: 1_302, y: 824))
  }

  func testFloatingDisplayOriginIsConstrainedInsideVisibleScreenBounds() {
    let visibleFrame = NSRect(x: 100, y: 50, width: 900, height: 700)
    let contentSize = NSSize(width: 110, height: 48)

    XCTAssertEqual(
      FloatingCountdownWindowController.constrainedOrigin(
        proposedOrigin: NSPoint(x: 2_000, y: 2_000),
        contentSize: contentSize,
        visibleFrame: visibleFrame
      ),
      NSPoint(x: 890, y: 702)
    )
    XCTAssertEqual(
      FloatingCountdownWindowController.constrainedOrigin(
        proposedOrigin: NSPoint(x: -500, y: -500),
        contentSize: contentSize,
        visibleFrame: visibleFrame
      ),
      NSPoint(x: 100, y: 50)
    )
  }

  func testSettingsCanOpenAfterDismissingAnEditingPanel() throws {
    _ = NSApplication.shared
    let panel = MenuPanel()
    let settingsController = SettingsWindowController()
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

    panel.dismiss(animated: false)

    XCTAssertFalse(panel.firstResponder === editingResponder)
    XCTAssertTrue(panel.firstResponder === panel)
    XCTAssertFalse(panel.isShown)

    settingsController.show()
    XCTAssertTrue(try XCTUnwrap(settingsController.window).isVisible)
  }
}

@MainActor
final class SettingsPresentationCoordinatorTests: XCTestCase {
  func testSettingsAreOrderedOnScreenBeforeTheMenuIsDismissed() {
    var events: [String] = []
    var scheduledAction: SettingsPresentationCoordinator.Action?

    SettingsPresentationCoordinator.present(
      dismissMenu: { events.append("dismiss") },
      orderSettingsOnScreen: { events.append("order") },
      activateSettings: { events.append("activate") },
      schedule: { action in
        events.append("schedule")
        scheduledAction = action
      }
    )

    // The window is ordered and made key synchronously while the popover is
    // still live. Only dismissal is deferred to the next runloop turn.
    XCTAssertEqual(events, ["order", "activate", "schedule"])
    XCTAssertNotNil(scheduledAction)
    scheduledAction?()
    XCTAssertEqual(events, ["order", "activate", "schedule", "dismiss"])
  }

  func testMenuIsDismissedOnlyAfterSettingsAreActivated() {
    var settingsActivated = false
    var scheduledAction: SettingsPresentationCoordinator.Action?

    SettingsPresentationCoordinator.present(
      dismissMenu: { XCTAssertTrue(settingsActivated) },
      orderSettingsOnScreen: {},
      activateSettings: { settingsActivated = true },
      schedule: { scheduledAction = $0 }
    )

    XCTAssertTrue(settingsActivated)
    // Dismissal is deferred, but Settings is already active.
    scheduledAction?()
  }
}

@MainActor
final class SettingsWindowControllerTests: XCTestCase {
  func testSettingsWindowKeepsCloseEnabledAndDisablesMinimizeAndZoom() throws {
    _ = NSApplication.shared
    let controller = SettingsWindowController()
    controller.show()
    let window = try XCTUnwrap(controller.window)
    defer { window.close() }

    XCTAssertTrue(window.styleMask.contains(.closable))
    XCTAssertTrue(window.styleMask.contains(.miniaturizable))
    XCTAssertTrue(window.styleMask.contains(.resizable))
    XCTAssertTrue(window.styleMask.contains(.nonactivatingPanel))
    XCTAssertTrue(window is NSPanel)
    XCTAssertEqual(window.level, .floating)
    XCTAssertFalse(try XCTUnwrap(window as? NSPanel).hidesOnDeactivate)
    XCTAssertFalse(window.collectionBehavior.contains(.transient))
    XCTAssertTrue(try XCTUnwrap(window.standardWindowButton(.closeButton)).isEnabled)
    XCTAssertFalse(try XCTUnwrap(window.standardWindowButton(.miniaturizeButton)).isEnabled)
    XCTAssertFalse(try XCTUnwrap(window.standardWindowButton(.zoomButton)).isEnabled)
  }

  func testClosingSettingsDiscardsTheWindowBeforeReopening() throws {
    _ = NSApplication.shared
    let controller = SettingsWindowController()
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
    let controller = SettingsWindowController()
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
