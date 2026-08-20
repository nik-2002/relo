import AppKit
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

private final class TonePreviewDelegate: NSObject, AVAudioPlayerDelegate {
  var didFinishPlaying: (() -> Void)?

  func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    didFinishPlaying?()
  }
}

struct AlertSettingsSection: View {
  @AppStorage(ReloSettingsKeys.tone) private var selectedTone = NotificationTone.default.rawValue
  @AppStorage(ReloSettingsKeys.repeatCount) private var repeatCount = NotificationRepeatOption.default.rawValue
  @AppStorage(ReloSettingsKeys.volumeLevel) private var alarmVolume = AlarmVolume.defaultLevel
  @AppStorage(ReloSettingsKeys.playSound) private var playSound = true
  @State private var previewPlayer: AVAudioPlayer?
  @State private var previewPlayers: [String: AVAudioPlayer] = [:]
  @State private var isPreviewing = false
  @State private var tonePreviewDelegate = TonePreviewDelegate()
  @State private var importedTone: ImportedTone?
  @State private var toneImportError: String?
  private let importedToneStore = ImportedToneStore()

  var body: some View {
    Section("Alerts") {
      Toggle("Play Sound", isOn: $playSound)
        .onChange(of: playSound) { _, enabled in
          if !enabled {
            stopPreviewTone()
          }
        }

      LabeledContent("Tone") {
        HStack(spacing: 6) {
          Picker("", selection: $selectedTone) {
            ForEach(NotificationTone.allCases) { tone in
              Text(tone.displayName)
                .tag(tone.rawValue)
            }
            if let importedTone {
              Text(importedTone.displayName)
                .tag(ImportedToneStore.selectionValue)
            }
          }
          .labelsHidden()
          .focusEffectDisabled()
          .pickerStyle(.menu)
          .frame(width: 125)

          Button {
            if isPreviewing {
              stopPreviewTone()
            } else {
              playPreviewTone(named: selectedTone)
            }
          } label: {
            Image(systemName: isPreviewing ? "stop.fill" : "play.fill")
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
          .help(isPreviewing ? "Stop Preview" : "Preview Tone")
          .accessibilityLabel(isPreviewing ? "Stop Preview" : "Preview Tone")
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

      LabeledContent("Volume") {
        HStack(spacing: 8) {
          Image(systemName: "speaker.fill")
            .foregroundStyle(.secondary)

          Slider(value: $alarmVolume, in: 0...1)
            .frame(width: 170)
            .accessibilityLabel("Alarm Volume")

          Image(systemName: "speaker.wave.3.fill")
            .foregroundStyle(.secondary)
        }
      }
      .disabled(!playSound)
    }
    .onAppear {
      alarmVolume = AlarmVolume.migrateIfNeeded()
      preloadPreviewTones()
      importedTone = importedToneStore.current()
      validateSelectedTone()
    }
    .onChange(of: alarmVolume) { _, newValue in
      previewPlayer?.volume = Float(AlarmVolume.clamped(newValue))
    }
    .onChange(of: selectedTone) { _, _ in
      stopPreviewTone()
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
    let url: URL?
    if rawValue == ImportedToneStore.selectionValue {
      url = importedTone?.url
    } else if let tone = NotificationTone(rawValue: rawValue) {
      url = tone.audioURL
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

    previewPlayer?.volume = Float(AlarmVolume.clamped(alarmVolume))
    previewPlayer?.currentTime = 0
    previewPlayer?.delegate = tonePreviewDelegate
    tonePreviewDelegate.didFinishPlaying = {
      DispatchQueue.main.async {
        isPreviewing = false
        previewPlayer = nil
      }
    }
    isPreviewing = previewPlayer?.play() == true
  }

  private func stopPreviewTone() {
    previewPlayer?.delegate = nil
    previewPlayer?.stop()
    previewPlayer?.currentTime = 0
    previewPlayer = nil
    tonePreviewDelegate.didFinishPlaying = nil
    isPreviewing = false
  }

  private func preloadPreviewTones() {
    guard previewPlayers.isEmpty else { return }
    let tones = NotificationTone.allCases
    DispatchQueue.global(qos: .userInitiated).async {
      var players: [String: AVAudioPlayer] = [:]
      for tone in tones {
        guard let url = tone.audioURL else { continue }
        if let player = try? AVAudioPlayer(contentsOf: url) {
          player.prepareToPlay()
          players[tone.rawValue] = player
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

}
