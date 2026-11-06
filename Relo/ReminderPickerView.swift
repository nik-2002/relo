import SwiftUI

/// The searchable reminder list that opens beside the menu card. A native
/// menu cannot hold a search field, so this lives in its own panel.
struct ReminderPickerView: View {
  static let willShowNotification = Notification.Name("ReloReminderPickerWillShow")
  static let completionDelay: Duration = .milliseconds(1_500)
  /// How long the Undo bar stays before a deleted reminder is really removed.
  static let deletionDelay: Duration = .seconds(4)
  /// Highlight ID of the "New reminder" row, which sits after the matches.
  static let newReminderRowID = "relo.new-reminder"

  let usesSystemPopoverSurface: Bool
  /// Starts a countdown for a reminder made here, unless one is already running.
  let startTimer: () -> Void
  let close: () -> Void

  @EnvironmentObject private var reminders: ReminderFocusStore
  @State private var query = ""
  @State private var highlightedID: String?
  @State private var pendingCompletionIDs: Set<String> = []
  @State private var pendingDeletion: FocusReminder?
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

        if let pendingDeletion {
          undoDeletionBar(for: pendingDeletion)
        }

        if showsNewReminderRow {
          Divider()
            .padding(.horizontal, 12)
          newReminderRow
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
        }

        if let error = reminders.completionError {
          Text(error)
            .font(.caption)
            .foregroundStyle(.red)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
      }
    }
    .frame(
      width: ReminderPickerPanel.contentSize.width,
      height: ReminderPickerPanel.contentSize.height,
      alignment: .top
    )
    .onReceive(NotificationCenter.default.publisher(for: Self.willShowNotification)) { _ in
      commitPendingDeletion()
      query = ""
      highlightedID = nil
      Task {
        await reminders.refresh()
        highlightedID = highlightableIDs.first
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

      TextField("Search or add a reminder", text: $query)
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
          highlightedID = highlightableIDs.first
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
    let groups = reminders.groupedReminders(matching: query)
    guard let hiddenID = pendingDeletion?.id else { return groups }
    return groups.compactMap { group in
      let remaining = group.reminders.filter { $0.id != hiddenID }
      guard !remaining.isEmpty else { return nil }
      return ReminderGroup(listTitle: group.listTitle, listColor: group.listColor, reminders: remaining)
    }
  }

  private var visibleReminders: [FocusReminder] {
    groups.flatMap(\.reminders)
  }

  private var showsNewReminderRow: Bool {
    reminders.newReminderList != nil
      && ReminderFocusStore.canCreate(from: query, existing: reminders.reminders)
  }

  private var highlightableIDs: [String] {
    visibleReminders.map(\.id) + (showsNewReminderRow ? [Self.newReminderRowID] : [])
  }

  private var reminderList: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 0) {
          if reminders.linkedReminder != nil, query.isEmpty {
            noReminderRow
          }

          let groups = groups
          if groups.isEmpty, !showsNewReminderRow {
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
    let isCompleting = pendingCompletionIDs.contains(reminder.id)
    let due = ReminderDueLabel.make(for: reminder)

    return HStack(alignment: .firstTextBaseline, spacing: 8) {
      completionRing(for: reminder, isCompleting: isCompleting)
        .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }

      Button {
        pick(reminder)
      } label: {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          Text(reminder.title)
            .lineLimit(2)
            .truncationMode(.tail)
            .foregroundStyle(isCompleting ? .secondary : .primary)
            .frame(maxWidth: .infinity, alignment: .leading)

          if let due, !isCompleting {
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
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .help(due.map { "Work on \(reminder.title) — due \($0.text)" } ?? "Work on \(reminder.title)")
      .accessibilityLabel(
        [reminder.title, reminder.listTitle, due.map { "due \($0.text)" }]
          .compactMap { $0 }
          .joined(separator: ", ")
      )
      .accessibilityHint("Links this reminder to the timer")
    }
    .font(.system(size: 13))
    .padding(.vertical, 5)
    .padding(.horizontal, 6)
    .background(
      RoundedRectangle(cornerRadius: 6, style: .continuous)
        .fill(isHighlighted ? Color.accentColor.opacity(0.18) : .clear)
    )
    .onHover { hovering in
      if hovering {
        highlightedID = reminder.id
      }
    }
    .contextMenu {
      contextMenu(for: reminder)
    }
    .animation(.easeOut(duration: 0.15), value: isCompleting)
  }

  @ViewBuilder
  private func contextMenu(for reminder: FocusReminder) -> some View {
    Button("Work on This") {
      pick(reminder)
    }
    Button("Open in Reminders") {
      reminders.openInReminders(reminder)
      close()
    }
    Button("Mark as Completed") {
      if !pendingCompletionIDs.contains(reminder.id) {
        toggleCompletion(of: reminder)
      }
    }
    Divider()
    Button("Delete", role: .destructive) {
      delete(reminder)
    }
  }

  /// Mirrors Reminders, which deletes without asking but offers Undo: the row
  /// disappears at once and is only removed from Reminders once the bar goes.
  private func delete(_ reminder: FocusReminder) {
    commitPendingDeletion()
    pendingCompletionIDs.remove(reminder.id)
    if highlightedID == reminder.id {
      moveHighlight(by: 1)
    }
    withAnimation(.easeOut(duration: 0.2)) {
      pendingDeletion = reminder
    }
    Task {
      try? await Task.sleep(for: Self.deletionDelay)
      guard pendingDeletion?.id == reminder.id else { return }
      commitPendingDeletion()
    }
  }

  private func commitPendingDeletion() {
    guard let reminder = pendingDeletion else { return }
    withAnimation(.easeOut(duration: 0.2)) {
      pendingDeletion = nil
    }
    _ = reminders.delete(reminder)
  }

  private func undoDeletionBar(for reminder: FocusReminder) -> some View {
    HStack(spacing: 8) {
      Text("Deleted “\(reminder.title)”")
        .lineLimit(1)
        .truncationMode(.middle)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
      Button("Undo") {
        withAnimation(.easeOut(duration: 0.2)) {
          pendingDeletion = nil
        }
      }
      .buttonStyle(.plain)
      .foregroundStyle(Color.accentColor)
      .keyboardShortcut("z", modifiers: .command)
    }
    .font(.system(size: 12))
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .transition(.move(edge: .bottom).combined(with: .opacity))
  }

  /// Adds the typed title to a list and starts working on it straight away.
  private var newReminderRow: some View {
    let isHighlighted = highlightedID == Self.newReminderRowID
    let title = query.trimmingCharacters(in: .whitespacesAndNewlines)

    return HStack(spacing: 8) {
      Button(action: createFromQuery) {
        HStack(spacing: 8) {
          Image(systemName: "plus.circle.fill")
            .font(.system(size: 13))
            .foregroundStyle(reminders.newReminderList?.color?.color ?? .accentColor)
            .frame(width: 14)
          Text("New “\(title)”")
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .help("Add “\(title)” to Reminders and start the timer")
      .accessibilityHint("Adds this reminder and starts the timer")

      listMenu
    }
    .font(.system(size: 13))
    .padding(.vertical, 5)
    .padding(.horizontal, 6)
    .background(
      RoundedRectangle(cornerRadius: 6, style: .continuous)
        .fill(isHighlighted ? Color.accentColor.opacity(0.18) : .clear)
    )
    .onHover { hovering in
      if hovering {
        highlightedID = Self.newReminderRowID
      }
    }
  }

  private var listMenu: some View {
    Menu {
      ForEach(reminders.lists) { list in
        Button {
          reminders.chooseNewReminderList(list)
        } label: {
          if list.id == reminders.newReminderListID {
            Label(list.title, systemImage: "checkmark")
          } else {
            Text(list.title)
          }
        }
      }
    } label: {
      Text(reminders.newReminderList?.title ?? "List")
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(reminders.newReminderList?.color?.color ?? .secondary)
        .lineLimit(1)
    }
    .menuStyle(.borderlessButton)
    .menuIndicator(.visible)
    .fixedSize()
    .help("Choose the list for the new reminder")
    .accessibilityLabel("List: \(reminders.newReminderList?.title ?? "none")")
  }

  private func createFromQuery() {
    guard reminders.createAndLink(title: query) else { return }
    startTimer()
    close()
  }

  /// Mirrors Reminders: clicking the ring fills it, and the reminder is
  /// completed after a short pause, during which a second click undoes it.
  private func completionRing(for reminder: FocusReminder, isCompleting: Bool) -> some View {
    let color = reminder.listColor?.color ?? .secondary
    return Button {
      toggleCompletion(of: reminder)
    } label: {
      ZStack {
        if isCompleting {
          Circle()
            .fill(color)
          Image(systemName: "checkmark")
            .font(.system(size: 7, weight: .heavy))
            .foregroundStyle(.white)
        } else {
          Circle()
            .strokeBorder(color, lineWidth: 1.5)
        }
      }
      .frame(width: 12, height: 12)
      .frame(width: 14, height: 14)
      .contentShape(Circle().inset(by: -4))
    }
    .buttonStyle(.plain)
    .help(isCompleting ? "Undo" : "Mark as completed")
    .accessibilityLabel(isCompleting ? "Undo completing \(reminder.title)" : "Complete \(reminder.title)")
  }

  private func toggleCompletion(of reminder: FocusReminder) {
    if pendingCompletionIDs.remove(reminder.id) != nil {
      return
    }
    pendingCompletionIDs.insert(reminder.id)
    Task {
      try? await Task.sleep(for: Self.completionDelay)
      guard pendingCompletionIDs.remove(reminder.id) != nil else { return }
      if highlightedID == reminder.id {
        moveHighlight(by: 1)
      }
      withAnimation(.easeOut(duration: 0.2)) {
        _ = reminders.complete(reminder)
      }
    }
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
    let ids = highlightableIDs
    guard let id = ids.first(where: { $0 == highlightedID }) ?? ids.first else { return }
    if id == Self.newReminderRowID {
      createFromQuery()
    } else if let reminder = visibleReminders.first(where: { $0.id == id }) {
      pick(reminder)
    }
  }

  private func moveHighlight(by offset: Int) {
    let ids = highlightableIDs
    guard !ids.isEmpty else { return }
    let currentIndex = ids.firstIndex { $0 == highlightedID } ?? -1
    let nextIndex = min(max(currentIndex + offset, 0), ids.count - 1)
    highlightedID = ids[nextIndex]
  }
}

extension ListColor {
  var color: Color {
    Color(.sRGB, red: red, green: green, blue: blue)
  }
}
