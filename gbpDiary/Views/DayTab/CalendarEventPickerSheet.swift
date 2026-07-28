#if os(macOS)
import SwiftUI
import AppKit

// Picks a macOS Calendar event to create a new meeting from. Shows a day's events (defaulting
// to the diary day), across every calendar the user has (Exchange + Gmail/CalDAV included).
// Selecting an event hands the draft back via `onPick`; the caller opens the meeting editor
// pre-filled. Handles the not-yet-authorized, denied, and empty states.
struct CalendarEventPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    /// The day to look up first (e.g. the diary day being viewed).
    var presetDate: Date = Date()
    /// Called with the chosen event just before the sheet dismisses.
    var onPick: (CalendarEventDraft) -> Void

    @State private var service = CalendarService()
    @State private var access: CalendarAccess = .notDetermined
    @State private var day: Date = Date()
    @State private var events: [CalendarEventDraft] = []

    var body: some View {
        NavigationStack {
            Group {
                switch access {
                case .authorized:     authorizedBody
                case .notDetermined:  ProgressView("Requesting calendar access…")
                case .denied, .restricted, .writeOnly: deniedBody
                }
            }
            .navigationTitle("New Meeting from Calendar")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                }
            }
        }
        .frame(minWidth: 480, minHeight: 420)
        .onAppear {
            day = Calendar.current.startOfDay(for: presetDate)
            access = service.access
            switch access {
            case .authorized:
                reload()
            case .notDetermined:
                service.requestAccess { granted in
                    access = granted
                    if granted == .authorized { reload() }
                }
            default:
                break
            }
        }
    }

    // MARK: - Authorized

    private var authorizedBody: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Day").foregroundStyle(.secondary)
                DatePicker("", selection: $day, displayedComponents: .date)
                    .labelsHidden()
                    .onChange(of: day) { _, _ in reload() }
                Spacer()
            }
            .padding()
            Divider()
            if events.isEmpty {
                ContentUnavailableView("No events", systemImage: "calendar",
                    description: Text("No calendar events on \(day.formatted(.dateTime.weekday().day().month())).") )
            } else {
                List(events) { event in
                    Button { onPick(event); dismiss() } label: { row(event) }
                        .buttonStyle(.plain)
                }
            }
        }
    }

    private func row(_ event: CalendarEventDraft) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(event.title.isEmpty ? "Untitled" : event.title)
            HStack(spacing: 10) {
                Text(timeLabel(event)).font(.caption).foregroundStyle(.secondary)
                if !event.attendees.isEmpty {
                    Label("\(event.attendees.count)", systemImage: "person.2")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func timeLabel(_ event: CalendarEventDraft) -> String {
        if event.isAllDay { return "All day" }
        let start = event.start.formatted(date: .omitted, time: .shortened)
        let end = event.end.formatted(date: .omitted, time: .shortened)
        return "\(start) – \(end)"
    }

    // MARK: - Denied

    private var deniedBody: some View {
        ContentUnavailableView {
            Label("Calendar access needed", systemImage: "calendar.badge.exclamationmark")
        } description: {
            Text("Allow gbpDiary to read your calendar in System Settings → Privacy & Security → Calendars.")
        } actions: {
            Button("Open System Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    private func reload() {
        events = service.events(on: day)
    }
}
#endif
