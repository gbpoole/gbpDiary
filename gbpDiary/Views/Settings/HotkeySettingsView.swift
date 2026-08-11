import SwiftUI
#if os(macOS)
import AppKit
#endif

// Settings ▸ Shortcuts. Lists every configurable app hotkey (`HotkeyAction`) grouped by section
// heading, with a click-to-record control and a per-row reset-to-default. New app-specific hotkeys
// appear here automatically once added to `HotkeyAction` (see CLAUDE.md).
struct HotkeySettingsView: View {
    @Environment(HotkeySettings.self) private var hotkeys

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(HotkeyAction.sections, id: \.self) { section in
                    GroupBox(section) {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(HotkeyAction.actions(in: section)) { action in
                                row(action)
                                if action != HotkeyAction.actions(in: section).last { Divider() }
                            }
                            if section == "Tabs" {
                                Text("Jump to a tab by position with ⌘1–⌘8 (and ⌘9 for the last tab). ⌘W closes the active tab, not the window.")
                                    .font(.caption).foregroundStyle(.secondary)
                                    .padding(.top, 2)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                HStack {
                    Spacer()
                    Button("Reset All to Defaults") { hotkeys.resetAll() }
                }
            }
            .padding()
        }
        .frame(minWidth: 460, minHeight: 300)
    }

    @ViewBuilder
    private func row(_ action: HotkeyAction) -> some View {
        let current = hotkeys.hotkey(for: action)
        let conflict = hotkeys.conflict(for: current, excluding: action)
        HStack(spacing: 10) {
            Text(action.title)
            if let conflict {
                Label("Also \(conflict.title)", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(AppTheme.warning)
                    .help("This shortcut is also assigned to \(conflict.title).")
            }
            Spacer()
            HotkeyRecordingField(current: current) { hotkeys.setHotkey($0, for: action) }
            Button {
                hotkeys.reset(action)
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .buttonStyle(.borderless)
            .help("Reset to default (\(action.defaultHotkey.display))")
            .disabled(!hotkeys.isCustomised(action))
        }
    }
}

// A click-to-record shortcut control: shows the current combo, and while recording swallows the next
// key-down to capture a new combo (Esc cancels). Requires a non-shift modifier to be a valid command.
struct HotkeyRecordingField: View {
    let current: Hotkey
    let onRecord: (Hotkey) -> Void

    @State private var recording = false
    #if os(macOS)
    @State private var monitor = HotkeyRecorderMonitor()
    #endif

    var body: some View {
        Button { toggle() } label: {
            Text(recording ? "Press shortcut…" : current.display)
                .font(.system(.body, design: .monospaced))
                .frame(minWidth: 104)
        }
        .buttonStyle(.bordered)
        .tint(recording ? AppTheme.accent : nil)
        #if os(macOS)
        .onDisappear { stopRecording() }
        #endif
    }

    private func toggle() {
        #if os(macOS)
        if recording { stopRecording() } else { startRecording() }
        #endif
    }

    #if os(macOS)
    private func startRecording() {
        recording = true
        monitor.onCapture = { hotkey in
            onRecord(hotkey)
            recording = false
            monitor.stop()
        }
        monitor.onCancel = {
            recording = false
            monitor.stop()
        }
        monitor.start()
    }

    private func stopRecording() {
        recording = false
        monitor.stop()
    }
    #endif
}

#if os(macOS)
// Swallows the next key-down while active and reports the captured `Hotkey` (Esc → cancel). Mirrors the
// app's other NSEvent monitors (KeyboardMonitors.swift). Only one field records at a time.
final class HotkeyRecorderMonitor: @unchecked Sendable {
    private var monitor: Any?
    var onCapture: ((Hotkey) -> Void)?
    var onCancel: (() -> Void)?

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 { // Esc cancels
                MainActor.assumeIsolated { self.onCancel?() }
                return nil
            }
            let hotkey = Hotkey(event: event)
            // Require a real command modifier; keep listening on a bare key so typing doesn't "stick".
            guard hotkey.isValid else { return nil }
            MainActor.assumeIsolated { self.onCapture?(hotkey) }
            return nil
        }
    }

    func stop() {
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }
}
#endif
