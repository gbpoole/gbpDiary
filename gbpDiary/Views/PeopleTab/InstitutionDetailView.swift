import SwiftUI
import SwiftData

struct InstitutionDetailView: View {
    @Bindable var institution: Institution

    @State private var showingEdit = false
    @State private var selectedPerson: Person?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                GroupBox("Members (\(institution.members.count))") {
                    if institution.members.isEmpty {
                        Text("No members.").foregroundStyle(.secondary)
                    } else {
                        ForEach(institution.members.sorted { $0.name < $1.name }) { person in
                            HStack {
                                Text(person.name)
                                if let email = person.email {
                                    Spacer()
                                    Link(email, destination: URL(string: "mailto:\(email)")!)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                GroupBox("Projects (\(institution.projects.count))") {
                    if institution.projects.isEmpty {
                        Text("No linked projects.").foregroundStyle(.secondary)
                    } else {
                        ForEach(institution.projects.filter { !$0.isCompleted }.sorted { $0.name < $1.name }) { p in
                            Text(p.name).padding(.vertical, 2)
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle(institution.name)
        .toolbar {
            ToolbarItem { Button { showingEdit = true } label: { Image(systemName: "pencil") } }
        }
        .sheet(isPresented: $showingEdit) { InstitutionEditorSheet(institution: institution) }
    }
}
