import SwiftUI
import SwiftData

/// How the user chose to reconcile an unrecognized scraped attendee.
enum AttendeeReconcileResult {
    case link(Person)                                    // existing person + add the scraped email
    case create(name: String, institution: Institution?) // brand-new person
}

// Reconciles a calendar-scraped attendee that matched no existing Person: either link them to an
// existing person (adding the scraped email to that person's list) or create a new person
// (name prefilled + optional institution). Styled to match the app's other edit modals.
struct ResolveAttendeeSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let attendee: CalendarAttendee
    var onResolve: (AttendeeReconcileResult) -> Void

    @Query(sort: \Person.name) private var people: [Person]
    @Query(sort: \Institution.name) private var institutions: [Institution]

    private enum Mode: String, CaseIterable {
        case existing = "Existing person"
        case new = "New person"
    }

    @State private var mode: Mode = .existing
    @State private var selectedPerson: Person?
    @State private var newName = ""
    @State private var selectedInstitution: Institution?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    Picker("", selection: $mode) {
                        ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    if mode == .existing { existingSection } else { newSection }
                }
                .padding()
            }
            .navigationTitle("Reconcile Attendee")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(mode == .existing ? "Link" : "Create") { confirm() }.disabled(!canConfirm)
                }
            }
        }
        .onAppear { newName = attendee.name }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 300)
        #endif
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Unrecognized attendee")
                .font(AppTheme.interfaceFont(size: 11, weight: .semibold))
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundStyle(AppTheme.mutedText)
            Text(attendee.name.isEmpty ? (attendee.email ?? "Unknown") : attendee.name)
                .font(.title2.weight(.semibold))
            if let e = attendee.email, !e.isEmpty, !attendee.name.isEmpty {
                Text(e).font(.callout).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppTheme.cardRaised.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Sections

    private var existingSection: some View {
        GroupBox("Link to an existing person") {
            VStack(alignment: .leading, spacing: 8) {
                FuzzyPickerField(
                    allItems: people,
                    selectedItem: $selectedPerson,
                    label: { $0.name },
                    chipColor: AppTheme.person,
                    tapArea: true,
                    emptyLabel: "Search people…"
                )
                if let e = attendee.email, !e.isEmpty {
                    Text("Adds \(e) to their emails.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var newSection: some View {
        GroupBox("Create a new person") {
            VStack(alignment: .leading, spacing: 12) {
                labeledField("Name") {
                    TextField("Name", text: $newName)
                        .textFieldStyle(.roundedBorder)
                }
                labeledField("Institution (optional)") {
                    FuzzyPickerField(
                        allItems: institutions,
                        selectedItem: $selectedInstitution,
                        label: { $0.name },
                        chipColor: AppTheme.institution,
                        onCreateItem: { makeInstitution($0) },
                        tapArea: true,
                        emptyLabel: "None — tap to choose or add"
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func labeledField<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            content()
        }
    }

    // MARK: - Actions

    private var canConfirm: Bool {
        switch mode {
        case .existing: return selectedPerson != nil
        case .new:      return !newName.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    private func confirm() {
        switch mode {
        case .existing:
            if let p = selectedPerson { onResolve(.link(p)) }
        case .new:
            let n = newName.trimmingCharacters(in: .whitespaces)
            guard !n.isEmpty else { return }
            onResolve(.create(name: n, institution: selectedInstitution))
        }
        dismiss()
    }

    // Create an Institution on the fly while picking one (auto-selected).
    private func makeInstitution(_ name: String) -> Institution? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let inst = Institution(name: trimmed)
        modelContext.insert(inst)
        return inst
    }
}
