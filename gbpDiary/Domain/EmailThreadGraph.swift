import Foundation

// Groups emails into threads by the actual **reply graph** (RFC Message-ID / In-Reply-To / References),
// JWZ-style — the deterministic replacement for subject guessing. Messages are connected when one
// references another's Message-ID (directly or transitively); each connected component is one thread with a
// stable `threadKey` (the lexicographically smallest id in the component, so the key is order-independent).
// Messages that carry NO reply headers fall back to grouping by normalized subject; a blank subject is its
// own thread. Pure + fully testable — no SwiftData, no Mail.
nonisolated struct ThreadableMessage: Equatable, Sendable {
    let id: String            // caller's stable local id (e.g. Mail's integer id, or the model UUID)
    let messageId: String     // RFC Message-ID, bare ("" if none)
    let inReplyTo: String?    // parent Message-ID, bare
    let references: [String]  // ancestor Message-IDs, bare
    let subject: String

    init(id: String, messageId: String = "", inReplyTo: String? = nil,
         references: [String] = [], subject: String = "") {
        self.id = id
        self.messageId = messageId
        self.inReplyTo = inReplyTo
        self.references = references
        self.subject = subject
    }

    /// The reply-link ids this message connects to (parent + ancestors), non-empty only.
    var links: [String] {
        var out: [String] = []
        if let irt = inReplyTo, !irt.isEmpty { out.append(irt) }
        out.append(contentsOf: references.filter { !$0.isEmpty })
        return out
    }
    /// Whether this message participates in the reply graph at all.
    var hasReplyInfo: Bool { !messageId.isEmpty || !links.isEmpty }
}

nonisolated enum EmailThreadGraph {
    /// Maps each message's `id` → its `threadKey`.
    static func assign(_ messages: [ThreadableMessage]) -> [String: String] {
        var uf = UnionFind()

        // Union each reply-graph message's own node with every id it links to.
        for m in messages where m.hasReplyInfo {
            let own = m.messageId.isEmpty ? "msg:\(m.id)" : m.messageId
            uf.add(own)
            for link in m.links { uf.union(own, link) }
        }

        // Per component, the smallest node id is the stable canonical key.
        var componentKey: [String: String] = [:]   // root → canonical (min) id
        for node in uf.nodes {
            let root = uf.find(node)
            if let existing = componentKey[root] {
                if node < existing { componentKey[root] = node }
            } else {
                componentKey[root] = node
            }
        }

        var result: [String: String] = [:]
        for m in messages {
            if m.hasReplyInfo {
                let own = m.messageId.isEmpty ? "msg:\(m.id)" : m.messageId
                let key = componentKey[uf.find(own)] ?? own
                result[m.id] = "id:\(key)"
            } else {
                // No reply headers → fall back to subject; blank subject stands alone.
                let subj = EmailThreading.normalizedSubject(m.subject)
                result[m.id] = subj.isEmpty ? "msg:\(m.id)" : "subj:\(subj)"
            }
        }
        return result
    }
}

// Minimal string union-find with path compression + union by size.
private struct UnionFind {
    private var parent: [String: String] = [:]
    private var size: [String: Int] = [:]

    var nodes: [String] { Array(parent.keys) }

    mutating func add(_ x: String) {
        if parent[x] == nil { parent[x] = x; size[x] = 1 }
    }

    mutating func find(_ x: String) -> String {
        add(x)
        var root = x
        while parent[root] != root { root = parent[root]! }
        // Path compression.
        var cur = x
        while parent[cur] != root { let next = parent[cur]!; parent[cur] = root; cur = next }
        return root
    }

    mutating func union(_ a: String, _ b: String) {
        let ra = find(a), rb = find(b)
        guard ra != rb else { return }
        let (sa, sb) = (size[ra] ?? 1, size[rb] ?? 1)
        if sa < sb { parent[ra] = rb; size[rb] = sa + sb }
        else { parent[rb] = ra; size[ra] = sa + sb }
    }
}
