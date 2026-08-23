import Foundation
import SwiftData

// Keeps `EmailConversation` entities in sync with the messages + reply graph. One code path serves both
// the one-time migration (build conversations from all existing emails, folding their legacy per-message
// state) and every ingest (attach new mail to its conversation, merging when a new reply bridges two).
//
// Conversation identity is *sticky*: an email already linked to a conversation keeps it, so the user's
// triage/project/person/importance/time on that conversation is never lost even as the graph's canonical
// threadKey shifts. New emails join the conversation of any message they reply to; a reply that connects
// two previously-separate conversations merges them.
@MainActor
enum EmailConversationReconciler {
    /// Reconcile the given emails (existing + newly-ingested) against their conversations. Creates, links,
    /// and merges conversations as needed; folds legacy per-message state onto newly-created conversations.
    static func reconcile(emails: [EmailMessage], context: ModelContext) {
        guard !emails.isEmpty else { return }

        // 1. Group emails by reply-graph threadKey.
        let threadable = emails.map {
            ThreadableMessage(id: $0.id.uuidString, messageId: $0.rfcMessageId,
                              inReplyTo: $0.inReplyTo, references: $0.references, subject: $0.subject)
        }
        let keyByEmail = EmailThreadGraph.assign(threadable)
        var groups: [String: [EmailMessage]] = [:]
        for e in emails { groups[keyByEmail[e.id.uuidString] ?? "msg:\(e.id.uuidString)", default: []].append(e) }

        // 2. Ensure one conversation per group; link members; merge duplicates.
        for (key, members) in groups {
            let owning = distinctConversations(of: members)
            let convo: EmailConversation
            if let survivor = owning.first {
                convo = survivor
                convo.threadKey = key
                for other in owning.dropFirst() { merge(other, into: convo, context: context) }
            } else {
                convo = EmailConversation(threadKey: key)
                context.insert(convo)
                seedFromLegacy(convo, members: members)   // no-op for fresh mail (empty legacy state)
            }
            for m in members where m.conversation?.id != convo.id { m.conversation = convo }
            if convo.person == nil { convo.person = members.first(where: { $0.person != nil })?.person }
        }

        // 3. Drop any conversation left with no messages (e.g. after a merge).
        let empties = (try? context.fetch(FetchDescriptor<EmailConversation>())) ?? []
        for c in empties where c.messages.isEmpty { context.delete(c) }
    }

    private static func distinctConversations(of members: [EmailMessage]) -> [EmailConversation] {
        var seen = Set<PersistentIdentifier>()
        var out: [EmailConversation] = []
        for m in members {
            if let c = m.conversation, seen.insert(c.persistentModelID).inserted { out.append(c) }
        }
        return out
    }

    // Seed a newly-created conversation from its members' legacy per-message state (migration). Fresh mail
    // has default legacy state, so this is a no-op for normal ingest.
    private static func seedFromLegacy(_ convo: EmailConversation, members: [EmailMessage]) {
        var seen = Set<PersistentIdentifier>()
        for m in members {
            for p in m.projects where seen.insert(p.persistentModelID).inserted { convo.projects.append(p) }
        }
        if convo.person == nil { convo.person = members.first(where: { $0.person != nil })?.person }
        let states = members.map {
            EmailThreadFold.MemberState(accepted: $0.accepted, dismissed: $0.dismissed, importance: $0.importance)
        }
        let folded = EmailThreadFold.fold(states)
        convo.accepted = folded.accepted
        convo.dismissed = folded.dismissed
        convo.importance = folded.importance
        for m in members {
            for entry in m.timeEntries where entry.conversation == nil { entry.conversation = convo }
        }
    }

    // Fold `other` into `survivor` (reassign its messages/time, union projects, keep the stronger state).
    private static func merge(_ other: EmailConversation, into survivor: EmailConversation, context: ModelContext) {
        guard other.id != survivor.id else { return }
        for m in other.messages { m.conversation = survivor }
        for e in other.timeEntries { e.conversation = survivor }
        for p in other.projects where !survivor.projects.contains(where: { $0.id == p.id }) {
            survivor.projects.append(p)
        }
        if survivor.person == nil { survivor.person = other.person }
        if other.accepted { survivor.accept() }
        if other.importance.rank > survivor.importance.rank { survivor.importance = other.importance }
        context.delete(other)
    }
}
