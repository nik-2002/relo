import Foundation

@MainActor
enum SettingsPresentationCoordinator {
  typealias Action = @MainActor () -> Void
  typealias Scheduler = (@escaping Action) -> Void

  static func present(
    dismissMenu: () -> Void,
    showSettings: @escaping Action = { @MainActor in
      SettingsWindowController.shared.show()
    },
    schedule: Scheduler = { action in
      DispatchQueue.main.async {
        action()
      }
    }
  ) {
    dismissMenu()
    schedule(showSettings)
  }
}
