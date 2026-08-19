import SwiftUI

struct MenuDismissAction {
  let action: () -> Void

  func callAsFunction() {
    action()
  }
}

struct MenuSecondaryToggleAction {
  let action: () -> Void

  func callAsFunction() {
    action()
  }
}

private struct MenuDismissKey: EnvironmentKey {
  static let defaultValue = MenuDismissAction {}
}

private struct MenuSecondaryToggleKey: EnvironmentKey {
  static let defaultValue = MenuSecondaryToggleAction {}
}

extension EnvironmentValues {
  var menuDismiss: MenuDismissAction {
    get { self[MenuDismissKey.self] }
    set { self[MenuDismissKey.self] = newValue }
  }

  var menuSecondaryToggle: MenuSecondaryToggleAction {
    get { self[MenuSecondaryToggleKey.self] }
    set { self[MenuSecondaryToggleKey.self] = newValue }
  }
}
