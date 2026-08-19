import SwiftUI

struct ReloSettingsView: View {
  var body: some View {
    VStack(alignment: .center, spacing: 16) {
      Text("Relo Settings")
        .font(.system(size: 22, weight: .semibold))
        .frame(maxWidth: .infinity, alignment: .center)

      Form {
        GeneralSettingsSection()
        TimerPresetSettingsSection()
        AlertSettingsSection()
        ShortcutSettingsSection()
      }
      .frame(width: 400)
    }
    .padding(20)
    .frame(width: 460)
  }
}

#Preview {
  ReloSettingsView()
}
