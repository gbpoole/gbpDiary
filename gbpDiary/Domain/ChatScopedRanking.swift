import Foundation

// Applies a parsed `ChatQueryScope` to hybrid-ranked chunks.
//
// Kind + project are a soft restriction: if filtering by them removes everything (e.g. a project link is
// missing from the metadata), fall back to the unscoped ranking so the user still gets an answer.
//
// An interval is a HARD bound: the user explicitly named a date window ("last week"), so out-of-window
// chunks are dropped with no fallback — returning nothing is correct when nothing falls in the window
// (otherwise a "last week" question could surface a February meeting).
nonisolated enum ChatScopedRanking {
    static func apply(_ ranked: [ChatRankedChunk], scope: ChatQueryScope) -> [ChatRankedChunk] {
        guard !scope.kinds.isEmpty || scope.projectName != nil || scope.interval != nil else { return ranked }

        let projectKey = scope.projectName?.lowercased()
        var filtered = ranked.filter { r in
            if !scope.kinds.isEmpty, !scope.kinds.contains(r.chunk.source.kind) { return false }
            if let projectKey, !r.chunk.projectNames.contains(projectKey) { return false }
            return true
        }
        if filtered.isEmpty { filtered = ranked }   // kind/project fallback (metadata may be missing)

        guard let interval = scope.interval else { return filtered }

        // Explicit date window: keep only in-window chunks, newest first. No out-of-window fallback.
        // Recency is the user's explicit ask, so date wins; importance only breaks exact date ties.
        return filtered
            .filter { $0.chunk.sortDate.map(interval.contains) ?? false }
            .sorted { a, b in
                let da = a.chunk.sortDate ?? .distantPast
                let db = b.chunk.sortDate ?? .distantPast
                if da != db { return da > db }      // recent first
                if a.chunk.importanceWeight != b.chunk.importanceWeight {
                    return a.chunk.importanceWeight > b.chunk.importanceWeight
                }
                return a.score > b.score
            }
    }
}
