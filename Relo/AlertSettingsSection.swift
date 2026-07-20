import AppKit
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

struct AlertSettingsSection: View {
  @AppStorage(ReloSettingsKeys.tone) private var selectedTone = NotificationTone.default.rawValue
  @AppStorage(ReloSettingsKeys.repeatCount) private var repeatCount = NotificationRepeatOption.default.rawValue
  @AppStorage(ReloSettingsKeys.volume) private var selectedVolume = NotificationVolume.default.rawValue
  @AppStorage(ReloSettingsKeys.playSound) private var playSound = true
  @AppStorage(ReloSettingsKeys.showNotifications) private var showNotifications = false
  @State private var previewPlayer: AVAudioPlayer?
  @State private var previewPlayers: [String: AVAudioPlayer] = [:]
  @State private var importedTone: ImportedTone?
  @State private var toneImportError: String?
  @State private var notificationError: String?
  private let importedToneStore = ImportedToneStore()

  var body: some View {
    Section("Alerts") {
      Toggle("Show Notification", isOn: $showNotifications)
        .onChange(of: showNotifications) { _, newValue in
          handleShowNotificationsChange(newValue)
        }

      if let notificationError {
        VStack(alignment: .leading, spacing: 4) {
          Text(notificationError)
            .font(.caption)
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
          Button("Open Notification Settings") {
            openNotificationSettings()
          }
          .controlSize(.small)
        }
      }

      Toggle("Play Sound", isOn: $playSound)
        .onChange(of: playSound) { _, enabled in
          if !enabled {
            stopPreviewTone()
          }
        }

      LabeledContent("Tone") {
        HStack(spacing: 6) {
          Picker("", selection: $selectedTone) {
            Section("Relo Sounds") {
              ForEach(NotificationTone.allCases) { tone in
                Text(tone.displayName)
                  .tag(tone.rawValue)
              }
            }
            if let importedTone {
              Section("Imported") {
                Text(importedTone.displayName)
                  .tag(ImportedToneStore.selectionValue)
              }
            }
          }
          .labelsHidden()
          .focusEffectDisabled()
          .pickerStyle(.menu)
          .frame(width: 125)

          Button {
            playPreviewTone(named: selectedTone)
          } label: {
            Image(systemName: "play.fill")
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
          .help("Preview Tone")
          .accessibilityLabel("Preview Tone")
        }
      }
      .disabled(!playSound)

      LabeledContent("Custom Tone") {
        HStack(spacing: 6) {
          Button(importedTone == nil ? "Import…" : "Replace…") {
            chooseImportedTone()
          }
          .controlSize(.small)

          if importedTone != nil {
            Button {
              removeImportedTone()
            } label: {
              Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Remove Imported Tone")
            .accessibilityLabel("Remove Imported Tone")
          }
        }
      }
      .disabled(!playSound)

      if let toneImportError {
        Text(toneImportError)
          .font(.caption)
          .foregroundStyle(.red)
          .fixedSize(horizontal: false, vertical: true)
      }

      Picker("Repeat", selection: $repeatCount) {
        ForEach(NotificationRepeatOption.allCases) { option in
          Text(option.displayName)
            .tag(option.rawValue)
        }
      }
      .focusEffectDisabled()
      .pickerStyle(.menu)
      .disabled(!playSound)

      Picker("Volume", selection: $selectedVolume) {
        ForEach(NotificationVolume.allCases) { volume in
          Text(volume.displayName)
            .tag(volume.rawValue)
        }
      }
      .focusEffectDisabled()
      .pickerStyle(.menu)
      .disabled(!playSound)
    }
    .onAppear {
      preloadPreviewTones()
      importedTone = importedToneStore.current()
      validateSelectedTone()
      refreshNotificationAuthorization()
    }
    .onDisappear {
      stopPreviewTone()
    }
    .onReceive(
      NotificationCenter.default.publisher(
        for: SettingsWindowController.settingsWillCloseNotification
      )
    ) { _ in
      stopPreviewTone()
    }
    .onReceive(
      NotificationCenter.default.publisher(
        for: SettingsWindowController.settingsDidResignKeyNotification
      )
    ) { _ in
      stopPreviewTone()
    }
  }

  private func validateSelectedTone() {
    if selectedTone == ImportedToneStore.selectionValue, importedTone == nil {
      selectedTone = NotificationTone.default.rawValue
    } else if selectedTone != ImportedToneStore.selectionValue,
              NotificationTone(rawValue: selectedTone) == nil {
      selectedTone = NotificationTone.default.rawValue
    }
  }

  private func playPreviewTone(named rawValue: String) {
    stopPreviewTone()
    let volume = NotificationVolume(rawValue: selectedVolume) ?? .default
    let url: URL?
    if rawValue == ImportedToneStore.selectionValue {
      url = importedTone?.url
    } else if let tone = NotificationTone(rawValue: rawValue) {
      url = Bundle.main.url(forResource: tone.rawValue, withExtension: "wav")
    } else {
      url = nil
    }
    guard let url else { return }

    if let cached = previewPlayers[rawValue] {
      previewPlayer = cached
    } else if let player = try? AVAudioPlayer(contentsOf: url) {
      previewPlayers[rawValue] = player
      previewPlayer = player
    }

    previewPlayer?.volume = volume.level
    previewPlayer?.currentTime = 0
    previewPlayer?.play()
  }

  private func stopPreviewTone() {
    previewPlayer?.stop()
    previewPlayer?.currentTime = 0
    previewPlayer = nil
  }

  private func preloadPreviewTones() {
    guard previewPlayers.isEmpty else { return }
    let tones = NotificationTone.allCases.map(\.rawValue)
    DispatchQueue.global(qos: .userInitiated).async {
      var players: [String: AVAudioPlayer] = [:]
      for tone in tones {
        guard let url = Bundle.main.url(forResource: tone, withExtension: "wav") else { continue }
        if let player = try? AVAudioPlayer(contentsOf: url) {
          player.prepareToPlay()
          players[tone] = player
        }
      }
      DispatchQueue.main.async {
        if self.previewPlayers.isEmpty {
          self.previewPlayers = players
        } else {
          self.previewPlayers.merge(players) { existing, _ in existing }
        }
      }
    }
  }

  private func chooseImportedTone() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.audio]
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    panel.message = "Choose an audio file to use as Relo’s timer tone."
    panel.prompt = "Import"
    panel.begin { response in
      guard response == .OK, let sourceURL = panel.url else { return }
      importTone(from: sourceURL)
    }
  }

  private func importTone(from sourceURL: URL) {
    let accessedSecurityScope = sourceURL.startAccessingSecurityScopedResource()
    defer {
      if accessedSecurityScope {
        sourceURL.stopAccessingSecurityScopedResource()
      }
    }

    guard let player = try? AVAudioPlayer(contentsOf: sourceURL), player.duration > 0 else {
      toneImportError = "Relo could not read that audio file."
      return
    }

    do {
      stopPreviewTone()
      previewPlayers.removeValue(forKey: ImportedToneStore.selectionValue)
      importedTone = try importedToneStore.importTone(from: sourceURL)
      selectedTone = ImportedToneStore.selectionValue
      toneImportError = nil
    } catch {
      toneImportError = "Relo could not import that audio file."
    }
  }

  private func removeImportedTone() {
    do {
      stopPreviewTone()
      previewPlayers.removeValue(forKey: ImportedToneStore.selectionValue)
      try importedToneStore.remove()
      importedTone = nil
      if selectedTone == ImportedToneStore.selectionValue {
        selectedTone = NotificationTone.default.rawValue
      }
      toneImportError = nil
    } catch {
      toneImportError = "Relo could not remove the imported tone."
    }
  }

  private func refreshNotificationAuthorization() {
    guard showNotifications else { return }
    let center = UNUserNotificationCenter.current()
    center.getNotificationSettings { settings in
      DispatchQueue.main.async {
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
          notificationError = nil
        case .notDetermined:
          break
        case .denied:
          showNotifications = false
          notificationError = "Notifications are disabled in System Settings."
        @unknown default:
          showNotifications = false
          notificationError = "Notifications are unavailable."
        }
      }
    }
  }

  private func handleShowNotificationsChange(_ enabled: Bool) {
    guard enabled else {
      notificationError = nil
      return
    }

    let center = UNUserNotificationCenter.current()
    center.getNotificationSettings { settings in
      DispatchQueue.main.async {
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
          notificationError = nil
        case .notDetermined:
          center.requestAuthorization(options: [.alert]) { granted, _ in
            DispatchQueue.main.async {
              if granted {
                notificationError = nil
              } else {
                showNotifications = false
                notificationError = "Notifications are disabled in System Settings."
              }
            }
          }
        case .denied:
          showNotifications = false
          notificationError = "Notifications are disabled in System Settings."
        @unknown default:
          showNotifications = false
          notificationError = "Notifications are unavailable."
        }
      }
    }
  }

  private func openNotificationSettings() {
    guard let url = URL(
      string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
    ) else { return }
    NSWorkspace.shared.open(url)
  }
}
