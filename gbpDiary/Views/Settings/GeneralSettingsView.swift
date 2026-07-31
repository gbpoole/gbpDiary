import SwiftUI
import SwiftData

// General preferences pane (⌘,). Lets the user pick which Person is "me" — used as the default
// assignee for new meeting action items. Follows the app's edit-modal style (ScrollView + GroupBox).
struct GeneralSettingsView: View {
    @Query(sort: \Person.name) private var people: [Person]
    @State private var mePerson: Person?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                GroupBox("Me") {
                    VStack(alignment: .leading, spacing: 8) {
                        FuzzyPickerField(
                            allItems: people,
                            selectedItem: $mePerson,
                            label: { $0.name },
                            chipColor: AppTheme.person,
                            tapArea: true,
                            emptyLabel: "Choose your person…"
                        )
                        Text("Used as the default assignee for new meeting action items.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
        }
        .frame(minWidth: 440, minHeight: 220)
        .onAppear { mePerson = people.first { $0.id == AppSettingsStore.myPersonID } }
        .onChange(of: mePerson) { _, person in AppSettingsStore.myPersonID = person?.id }
    }
}
