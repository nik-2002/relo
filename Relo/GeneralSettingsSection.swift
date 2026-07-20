import ServiceManagement
import SwiftUI

struct GeneralSettingsSection: View {
  @AppStorage(ReloSettingsKeys.defaultUnit) private var defaultUnit = DefaultTimeUnit.default.rawValue
  @State private var launchAtLogin = false
  @State private var isUpdatingLaunchAtLogin = false
  @State private var launchAtLoginError: String?

  var body: some View {
    Section("General") {
      Toggle("Launch at Login", isOn: $launchAtLogin)
        .onChange(of: launchAtLogin) { _, newValue in
          guard !isUpdatingLaunchAtLogin else { return }
          setLaunchAtLogin(newValue)
        }

      if let launchAtLoginError {
        Text(launchAtLoginError)
          .font(.caption)
          .foregroundStyle(.red)
          .fixedSize(horizontal: false, vertical: true)
      }

      Picker("Default Unit", selection: $defaultUnit) {
        ForEach(DefaultTimeUnit.allCases) { unit in
          Text(unit.displayName)
            .tag(unit.rawValue)
        }
      }
      .focusEffectDisabled()
      .pickerStyle(.menu)
    }
    .onAppear {
      refreshLaunchAtLoginState()
    }
  }

  private func refreshLaunchAtLoginState() {
    guard #available(macOS 13.0, *) else { return }
    isUpdatingLaunchAtLogin = true
    launchAtLogin = SMAppService.mainApp.status == .enabled
    isUpdatingLaunchAtLogin = false
  }

  private func setLaunchAtLogin(_ enabled: Bool) {
    guard #available(macOS 13.0, *) else { return }
    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
      launchAtLoginError = nil
    } catch {
      launchAtLoginError = "Could not update login item."
    }
    refreshLaunchAtLoginState()
  }
}
