#if os(macOS)
import SwiftUI

// Settings pane (⌘,) for calendar import: pick which calendars are pre-selected (filtered on) when
// importing an event into a new meeting. None selected = all calendars shown. Persisted via
// AppSettingsStore.defaultCalendarIDs.
struct CalendarSettingsView: View {
    @State private var service = CalendarService()
    @State private var calendars: [CalendarInfo] = []
    @State private var selected: Set<String> = []
    @State private var access: CalendarAccess = .notDetermined

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                GroupBox("Default import calendars") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("When importing an event into a new meeting, only these calendars are shown by default (you can still toggle others in the picker). None selected = all calendars.")
                            .font(.caption).foregroundStyle(.secondary)
                        content
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
        }
        .frame(minWidth: 460, minHeight: 320)
        .onAppear { setup() }
    }

    @ViewBuilder private var content: some View {
        switch access {
        case .authorized:
            if calendars.isEmpty {
                Text("No calendars found.").font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(calendars) { cal in
                    Toggle(cal.title, isOn: Binding(
                        get: { selected.contains(cal.id) },
                        set: { on in
                            if on { selected.insert(cal.id) } else { selected.remove(cal.id) }
                            AppSettingsStore.defaultCalendarIDs = selected
                        }
                    ))
                    .toggleStyle(.checkbox)
                }
            }
        case .notDetermined:
            Button("Enable calendar access") { requestAccess() }
        default:
            Button("Enable calendar access in System Settings…") { openCalendarSettings() }
        }
    }

    private func setup() {
        selected = AppSettingsStore.defaultCalendarIDs
        access = service.access
        if access == .authorized { calendars = service.calendars() }
        else if access == .notDetermined { requestAccess() }
    }

    private func requestAccess() {
        service.requestAccess { granted in
            access = granted
            if granted == .authorized { calendars = service.calendars() }
        }
    }

    private func openCalendarSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }
}
#endif
