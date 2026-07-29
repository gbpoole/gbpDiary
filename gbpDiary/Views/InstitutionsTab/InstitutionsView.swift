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
        .sheet(item: $selectedInstitution) { InstitutionEditorSheet(institution: $0) }
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
    @Environment(WorkspaceModel.self) private var workspace

    let institution: Institution?
    @State private var name = ""
    @State private var showingDeleteConfirm = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    GroupBox("Name") {
                        TextField("Name", text: $name)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: .infinity)
                    }
                    if let inst = institution {
                        GroupBox("Members (\(inst.members.count))") {
                            membersList(inst)
                        }
                        GroupBox("Projects (\(inst.projects.count))") {
                            projectsList(inst)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle(institution == nil ? "New Institution" : "Edit Institution")
            .toolbar {
                if institution != nil {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Delete") { showingDeleteConfirm = true }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                    }
                }
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(institution == nil ? "Add" : "Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .alert("Delete Institution?", isPresented: $showingDeleteConfirm) {
                Button("Delete", role: .destructive) { deleteInstitution() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently deletes the institution. Its members and projects are kept but no longer reference it.")
            }
        }
        .onAppear { name = institution?.name ?? "" }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 320)
        #endif
    }

    @ViewBuilder private func membersList(_ inst: Institution) -> some View {
        if inst.members.isEmpty {
            Text("No members.").foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(inst.members.sorted { $0.name < $1.name }) { person in
                    HStack {
                        Text(person.name)
                        if let email = person.primaryEmail {
                            Spacer()
                            Text(email).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private func projectsList(_ inst: Institution) -> some View {
        if inst.projects.isEmpty {
            Text("No linked projects.").foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(inst.projects.sorted { $0.name < $1.name }) { p in
                    Text(p.name)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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

    private func deleteInstitution() {
        guard let inst = institution else { return }
        workspace.closeEntity(inst.persistentModelID)
        modelContext.delete(inst)
        dismiss()
    }
}
