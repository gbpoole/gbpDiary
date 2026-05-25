import SwiftUI
import SwiftData

struct InstitutionsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Institution.name) private var institutions: [Institution]

    @State private var selectedInstitution: Institution?
    @State private var showingAddInstitution = false

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedInstitution) {
                ForEach(institutions) { institution in
                    Text(institution.name)
                        .tag(institution)
                }
            }
            .navigationTitle("Institutions")
            .toolbar {
                ToolbarItem {
                    Button { showingAddInstitution = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        } detail: {
            if let institution = selectedInstitution {
                InstitutionDetailView(institution: institution)
            } else {
                ContentUnavailableView("Select an Institution",
                                       systemImage: "building.2",
                                       description: Text("Choose an institution from the sidebar."))
            }
        }
        .sheet(isPresented: $showingAddInstitution) {
            InstitutionEditorSheet(institution: nil)
        }
    }
}

struct InstitutionEditorSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let institution: Institution?
    @State private var name = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
            }
            .navigationTitle(institution == nil ? "New Institution" : "Edit Institution")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(institution == nil ? "Add" : "Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .onAppear { name = institution?.name ?? "" }
        #if os(macOS)
        .frame(minWidth: 320, minHeight: 160)
        #endif
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        if let inst = institution {
            inst.name = trimmed
            inst.updatedAt = Date()
        } else {
            modelContext.insert(Institution(name: trimmed))
        }
        dismiss()
    }
}
