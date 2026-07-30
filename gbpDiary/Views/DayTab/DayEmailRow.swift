import SwiftUI

// A read-only row for one cached email on the diary day: direction icon + sender + subject caption
// + time chip. Mirrors DayDocumentRow's layout.
struct DayEmailRow: View {
    let email: EmailMessage

    private var sender: String {
        if let name = email.fromName, !name.isEmpty { return name }
        return email.fromAddress.isEmpty ? "Unknown sender" : email.fromAddress
    }

    // Person chip (green when linked, yellow "unrecognized" otherwise) + one chip per linked project.
    @ViewBuilder private var metaChips: some View {
        if let person = email.person {
            Chip(label: person.name, color: AppTheme.person)
        } else {
            Chip(label: email.fromName?.isEmpty == false ? email.fromName! : (email.fromAddress.isEmpty ? "Unrecognized" : email.fromAddress),
                 color: AppTheme.warning)
        }
        ForEach(email.projects) { project in
            Chip(label: project.name, color: AppTheme.project)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: email.direction == .sent ? "paperplane" : "envelope")
                .foregroundStyle(.secondary)
                .font(.system(size: 14))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(sender).lineLimit(1)
                    if email.direction == .sent {
                        Chip(label: "Sent", color: .gray)
                    }
                    Spacer(minLength: 0)
                    Chip(label: email.date.formatted(date: .omitted, time: .shortened), color: .gray)
                }
                Text(email.subject.isEmpty ? "(no subject)" : email.subject)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                FlowLayout(spacing: 4) { metaChips }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}
