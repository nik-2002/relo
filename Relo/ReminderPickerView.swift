import SwiftUI

/// The searchable reminder list that opens beside the menu card. A native
/// menu cannot hold a search field, so this lives in its own panel.
struct ReminderPickerView: View {
  static let willShowNotification = Notification.Name("ReloReminderPickerWillShow")

  let usesSystemPopoverSurface: Bool
  let close: () -> Void

  @EnvironmentObject private var reminders: ReminderFocusStore
  @State private var query = ""
  @State private var highlightedID: String?
  @FocusState private var isSearchFocused: Bool

  var body: some View {
    if usesSystemPopoverSurface {
      content
    } else {
      content.reloMenuSurface()
    }
  }

  private var content: some View {
    VStack(spacing: 0) {
      searchField
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 8)

      Divider()
        .padding(.horizontal, 12)

      switch reminders.access {
      case .notDetermined:
        accessMessage(
          "Relo needs access to Reminders to list your tasks.",
          buttonTitle: "Allow Access…"
        ) {
          Task { await reminders.requestAccess() }
        }
      case .denied:
        accessMessage(
          "Reminders access is turned off for Relo.",
          buttonTitle: "Open System Settings…"
        ) {
          reminders.openPrivacySettings()
        }
      case .granted:
        reminderList
      }
    }
    .frame(
      width: ReminderPickerPanel.contentSize.width,
      height: ReminderPickerPanel.contentSize.height,
      alignment: .top
    )
    .onReceive(NotificationCenter.default.publisher(for: Self.willShowNotification)) { _ in
      query = ""
      highlightedID = nil
      Task {
        await reminders.refresh()
        highlightedID = visibleReminders.first?.id
      }
      DispatchQueue.main.async {
        isSearchFocused = true
      }
    }
  }

  private var searchField: some View {
    HStack(spacing: 6) {
      Image(systemName: "magnifyingglass")
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.secondary)

      TextField("Search reminders", text: $query)
        .textFieldStyle(.plain)
        .font(.system(size: 13))
        .focused($isSearchFocused)
        .onSubmit(pickHighlighted)
        .onKeyPress(.downArrow) {
          moveHighlight(by: 1)
          return .handled
        }
        .onKeyPress(.upArrow) {
          moveHighlight(by: -1)
          return .handled
        }
        .onChange(of: query) { _, _ in
          highlightedID = visibleReminders.first?.id
        }

      if !query.isEmpty {
        Button {
          query = ""
        } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(.tertiary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Clear search")
      }
    }
    .padding(.vertical, 5)
    .padding(.horizontal, 8)
    .reloNestedContentFill()
  }

  private var groups: [ReminderGroup] {
    reminders.groupedReminders(matching: query)
  }

  private var visibleReminders: [FocusReminder] {
    groups.flatMap(\.reminders)
  }

  private var reminderList: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 0) {
          if reminders.linkedReminder != nil, query.isEmpty {
            noReminderRow
          }

          let groups = groups
          if groups.isEmpty {
            Text(query.isEmpty ? "No open reminders" : "No matches")
              .font(.system(size: 12))
              .foregroundStyle(.secondary)
              .frame(maxWidth: .infinity)
              .padding(.top, 24)
          }

          ForEach(groups) { group in
            listHeader(group)
            ForEach(group.reminders) { reminder in
              row(for: reminder)
                .id(reminder.id)
            }
          }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
      }
      .onChange(of: highlightedID) { _, id in
        guard let id else { return }
        proxy.scrollTo(id)
      }
    }
  }

  private var noReminderRow: some View {
    Button {
      reminders.unlink()
      close()
    } label: {
      HStack(spacing: 8) {
        Image(systemName: "circle.dashed")
          .font(.system(size: 12))
          .foregroundStyle(.tertiary)
          .frame(width: 14)
        Text("No reminder")
          .foregroundStyle(.secondary)
        Spacer()
      }
      .font(.system(size: 13))
      .padding(.vertical, 5)
      .padding(.horizontal, 6)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  private func listHeader(_ group: ReminderGroup) -> some View {
    Text(group.listTitle.isEmpty ? "Reminders" : group.listTitle)
      .font(.system(size: 11, weight: .semibold))
      .foregroundStyle(group.listColor?.color ?? .secondary)
      .padding(.horizontal, 6)
      .padding(.top, 10)
      .padding(.bottom, 3)
  }

  private func row(for reminder: FocusReminder) -> some View {
    let isLinked = reminder.id == reminders.linkedReminder?.id
    let isHighlighted = reminder.id == highlightedID
    let due = ReminderDueLabel.make(for: reminder)

    return Button {
      pick(reminder)
    } label: {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Circle()
          .strokeBorder(reminder.listColor?.color ?? .secondary, lineWidth: 1.5)
          .frame(width: 12, height: 12)
          .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
          .frame(width: 14)

        Text(reminder.title)
          .lineLimit(2)
          .truncationMode(.tail)
          .frame(maxWidth: .infinity, alignment: .leading)

        if let due {
          Text(due.text)
            .font(.system(size: 11).monospacedDigit())
            .foregroundStyle(due.isOverdue ? Color.red : Color.secondary)
            .lineLimit(1)
            .fixedSize()
        }

        if isLinked {
          Image(systemName: "checkmark")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
        }
      }
      .font(.system(size: 13))
      .padding(.vertical, 5)
      .padding(.horizontal, 6)
      .background(
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .fill(isHighlighted ? Color.accentColor.opacity(0.18) : .clear)
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { hovering in
      if hovering {
        highlightedID = reminder.id
      }
    }
    .help(due.map { "\(reminder.title) — due \($0.text)" } ?? reminder.title)
    .accessibilityLabel(
      [reminder.title, reminder.listTitle, due.map { "due \($0.text)" }]
        .compactMap { $0 }
        .joined(separator: ", ")
    )
  }

  private func accessMessage(
    _ message: String,
    buttonTitle: String,
    action: @escaping () -> Void
  ) -> some View {
    VStack(spacing: 10) {
      Text(message)
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
      Button(buttonTitle, action: action)
        .controlSize(.small)
    }
    .padding(20)
    .frame(maxWidth: .infinity)
  }

  private func pick(_ reminder: FocusReminder) {
    reminders.link(reminder)
    close()
  }

  private func pickHighlighted() {
    let visible = visibleReminders
    guard let reminder = visible.first(where: { $0.id == highlightedID }) ?? visible.first else {
      return
    }
    pick(reminder)
  }

  private func moveHighlight(by offset: Int) {
    let visible = visibleReminders
    guard !visible.isEmpty else { return }
    let currentIndex = visible.firstIndex { $0.id == highlightedID } ?? -1
    let nextIndex = min(max(currentIndex + offset, 0), visible.count - 1)
    highlightedID = visible[nextIndex].id
  }
}

extension ListColor {
  var color: Color {
    Color(.sRGB, red: red, green: green, blue: blue)
  }
}
