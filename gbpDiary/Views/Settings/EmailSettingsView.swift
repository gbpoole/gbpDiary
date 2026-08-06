import SwiftUI

// Preferences pane (Cmd-,) for the diary Email section: which Mail account and Inbox/Sent mailbox to
// read. Pickers are populated live from Mail so names match exactly (avoids typos). No credentials —
// Mail holds those. Follows the app's edit-modal style (ScrollView + GroupBox + rounded controls).
struct EmailSettingsView: View {
    @State private var accountName = ""
    @State private var inboxMailbox = ""
    @State private var sentMailbox = ""
    @State private var accounts: [String] = []
    @State private var mailboxes: [String] = []
    @State private var service = MailScriptService()
    @State private var status: String?
    @State private var excludeRules: [String] = []
    @State private var newRule = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                GroupBox("Mail account") {
                    VStack(alignment: .leading, spacing: 10) {
                        row("Account", selection: $accountName, options: options(accounts, accountName))
                            .onChange(of: accountName) { _, _ in loadMailboxes() }
                        Button("Reload from Mail") { loadAccounts() }
                    }
                }
                GroupBox("Mailboxes") {
                    VStack(alignment: .leading, spacing: 10) {
                        row("Inbox", selection: $inboxMailbox, options: options(mailboxes, inboxMailbox))
                        row("Sent", selection: $sentMailbox, options: options(mailboxes, sentMailbox))
                    }
                }
                GroupBox("Excluded senders") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Emails from these senders are dismissed automatically when fetched. A rule is a full address (news@x.com) or a domain (x.com or @x.com). Applies to newly-fetched email only.")
                            .font(.caption).foregroundStyle(.secondary)
                        ForEach(excludeRules, id: \.self) { rule in
                            HStack(spacing: 6) {
                                Text(rule).font(.callout)
                                Spacer(minLength: 0)
                                Button { removeRule(rule) } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        HStack(spacing: 6) {
                            TextField("address or domain…", text: $newRule)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit { addRule() }
                            Button("Add") { addRule() }
                                .disabled(EmailExcludeMatching.normalize(newRule) == nil)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack(spacing: 12) {
                    Button("Save") { save() }.keyboardShortcut(.defaultAction)
                    if let status { Text(status).font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                }
                Text("Reads the selected account's Inbox and Sent mailboxes via Mail. Requires the one-time Automation permission (Privacy & Security → Automation).")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding()
        }
        .frame(minWidth: 440, minHeight: 360)
        .onAppear {
            let s = EmailSettingsStore.load()
            accountName = s.accountName; inboxMailbox = s.inboxMailbox; sentMailbox = s.sentMailbox
            excludeRules = EmailExcludeStore.load()
            loadAccounts()
        }
    }

    private func addRule() {
        EmailExcludeStore.add(newRule)
        excludeRules = EmailExcludeStore.load()
        newRule = ""
    }

    private func removeRule(_ rule: String) {
        EmailExcludeStore.remove(rule)
        excludeRules = EmailExcludeStore.load()
    }

    private func row(_ label: String, selection: Binding<String>, options: [String]) -> some View {
        HStack(spacing: 8) {
            Text(label).frame(width: 70, alignment: .leading).font(.callout).foregroundStyle(.secondary)
            Picker("", selection: selection) {
                ForEach(options, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
        }
    }

    /// Ensures the current value is always selectable even before/if Mail enumeration returns.
    private func options(_ list: [String], _ current: String) -> [String] {
        var opts = list
        if !current.isEmpty, !opts.contains(current) { opts.insert(current, at: 0) }
        return opts
    }

    private func loadAccounts() {
        service.listAccounts { result in
            switch result {
            case .success(let names):
                accounts = names
                if accountName.isEmpty, let first = names.first { accountName = first }
                loadMailboxes()
            case .failure(let e): status = e.userMessage
            }
        }
    }

    private func loadMailboxes() {
        guard !accountName.isEmpty else { return }
        service.listMailboxes(account: accountName) { result in
            switch result {
            case .success(let names): mailboxes = names
            case .failure(let e): status = e.userMessage
            }
        }
    }

    private func save() {
        EmailSettingsStore.save(EmailSettings(accountName: accountName, inboxMailbox: inboxMailbox, sentMailbox: sentMailbox))
        status = "Saved."
    }
}
