import SwiftUI
import SwiftData

struct InstitutionsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Institution.name) private var institutions: [Institution]

    @State private var selectedInstitution: Institution?
    @State private var showingAddInstitution = false

    var body: some View {
        VStack(spacing: 0) {
            institutionTable
        }
        .navigationTitle("Institutions")
        .toolbar {
            ToolbarItem {
                Button { showingAddInstitution = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(item: $selectedInstitution) { InstitutionDetailView(institution: $0, asSheet: true) }
        .sheet(isPresented: $showingAddInstitution) { InstitutionEditorSheet(institution: nil) }
    }

    #if os(macOS)
    private var institutionTable: some View {
        Table(institutions) {
            TableColumn("Name") { institution in
                Text(institution.name)
                    .lineLimit(1)
                    .font(AppTheme.bodyFont(size: 13))
                    .foregroundStyle(AppTheme.text)
                    .onTapGesture { selectedInstitution = institution }
            }
            TableColumn("Members") { institution in
                Text("\(institution.members.count)")
                    .foregroundStyle(AppTheme.mutedText)
            }
            .width(80)
            TableColumn("Projects") { institution in
                Text("\(institution.projects.count)")
                    .foregroundStyle(AppTheme.mutedText)
            }
            .width(80)
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
    }
    #else
    private var institutionTable: some View {
        List(institutions) { institution in
            Text(institution.name)
                .onTapGesture { selectedInstitution = institution }
        }
    }
    #endif
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
