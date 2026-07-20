import AppKit
import SwiftUI

struct ReloSettingsView: View {
  var body: some View {
    VStack(alignment: .center, spacing: 16) {
      HStack(spacing: 12) {
        AppIconView()
          .frame(width: 48, height: 48)
        Text("Relo Settings")
          .font(.system(size: 22, weight: .semibold))
      }
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

private struct AppIconView: View {
  private var bundledIcon: NSImage {
    guard let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
          let icon = NSImage(contentsOf: iconURL) else {
      return NSApp.applicationIconImage
    }
    return icon
  }

  var body: some View {
    Image(nsImage: bundledIcon)
      .resizable()
      .scaledToFit()
  }
}

#Preview {
  ReloSettingsView()
}
