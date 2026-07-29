import SwiftUI

// Edits an ordered list of email addresses. The first entry is the primary (used wherever a
// single email is needed). Rows can be reordered (each non-first row has a "Set primary" button
// that moves it to the front) and deleted; new emails are appended with case-insensitive dedup.
struct EmailListEditor: View {
    @Binding var emails: [String]
    @State private var newEmail = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(emails.enumerated()), id: \.offset) { index, email in
                HStack(spacing: 8) {
                    if index == 0 {
                        Chip(label: "Primary", color: AppTheme.accent)
                    } else {
                        Button { setPrimary(index) } label: {
                            Image(systemName: "arrow.up.to.line").font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(AppTheme.accent)
                        .help("Set as primary")
                    }
                    Text(email).lineLimit(1)
                    Spacer(minLength: 0)
                    Button { emails.remove(at: index) } label: {
                        Image(systemName: "xmark.circle.fill").font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Remove")
                }
            }
            HStack(spacing: 6) {
                TextField("Add email…", text: $newEmail)
                    .textContentType(.emailAddress)
                    .onSubmit(addEmail)
                Button(action: addEmail) { Image(systemName: "plus.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppTheme.accent)
                    .disabled(newEmail.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func addEmail() {
        let updated = Person.appendingEmail(newEmail, to: emails)
        if updated != emails { emails = updated }
        newEmail = ""
    }

    private func setPrimary(_ index: Int) {
        guard emails.indices.contains(index), index != 0 else { return }
        let email = emails.remove(at: index)
        emails.insert(email, at: 0)
    }
}
