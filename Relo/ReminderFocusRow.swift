import SwiftUI

/// The single "for: …" line on the menu card. Picking a reminder is optional;
/// once a countdown has finished, the line asks whether the task is done.
struct ReminderFocusRow: View {
  @EnvironmentObject private var model: ReloModel
  @EnvironmentObject private var reminders: ReminderFocusStore

  var body: some View {
    Group {
      if model.isFinished, let linked = reminders.linkedReminder {
        completionPrompt(for: linked)
      } else {
        picker
      }
    }
    .font(.system(size: 12, weight: .medium))
    .frame(maxWidth: .infinity, alignment: .leading)
    .task {
      await reminders.refresh()
    }
  }

  private var picker: some View {
    Menu {
      menuContent
    } label: {
      HStack(spacing: 5) {
        Image(systemName: reminders.linkedReminder == nil ? "circle.dashed" : "circle")
          .font(.system(size: 11, weight: .regular))
        Text(reminders.linkedReminder.map { "for: \($0.title)" } ?? "for a reminder…")
          .lineLimit(1)
          .truncationMode(.tail)
      }
      .foregroundStyle(reminders.linkedReminder == nil ? .tertiary : .secondary)
      .contentShape(Rectangle())
    }
    .menuStyle(.button)
    .buttonStyle(.plain)
    .menuIndicator(.hidden)
    .fixedSize(horizontal: false, vertical: true)
    .help(reminders.linkedReminder?.title ?? "Commit this timer to a reminder")
    .accessibilityLabel(
      reminders.linkedReminder.map { "Working on \($0.title)" } ?? "Choose a reminder to work on"
    )
  }

  @ViewBuilder
  private var menuContent: some View {
    switch reminders.access {
    case .notDetermined:
      Button("Allow Access to Reminders…") {
        Task { await reminders.requestAccess() }
      }
    case .denied:
      Button("Allow Access in System Settings…") {
        reminders.openPrivacySettings()
      }
    case .granted:
      if reminders.linkedReminder != nil {
        Button("No Reminder") {
          reminders.unlink()
        }
        Divider()
      }

      let groups = reminders.groupedReminders
      if groups.isEmpty {
        Text("No open reminders")
      }
      ForEach(groups) { group in
        Section(group.listTitle) {
          ForEach(group.reminders) { reminder in
            Button {
              reminders.link(reminder)
            } label: {
              if reminder.id == reminders.linkedReminder?.id {
                Label(reminder.title, systemImage: "checkmark")
              } else {
                Text(reminder.title)
              }
            }
          }
        }
      }
    }
  }

  private func completionPrompt(for linked: FocusReminder) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      completionButtons(for: linked)

      if let error = reminders.completionError {
        Text(error)
          .font(.caption)
          .foregroundStyle(.red)
      }
    }
  }

  private func completionButtons(for linked: FocusReminder) -> some View {
    HStack(spacing: 6) {
      Text(linked.title)
        .lineLimit(1)
        .truncationMode(.tail)
        .foregroundStyle(.secondary)
        .help(linked.title)

      Spacer(minLength: 4)

      Button("done") {
        if reminders.completeLinkedReminder() {
          model.stop()
        }
      }
      .buttonStyle(.plain)
      .help("Mark “\(linked.title)” as completed in Reminders")

      Button("not yet") {
        model.stop()
      }
      .buttonStyle(.plain)
      .foregroundStyle(.secondary)
      .help("Keep the reminder open and linked")
    }
  }
}
