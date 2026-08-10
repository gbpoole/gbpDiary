import Foundation

nonisolated struct ChatSemanticIndexReport: Equatable, Sendable {
    let added: Int
    let updated: Int
    let unchanged: Int
    let deleted: Int
}

nonisolated struct ChatSemanticIndexSnapshot: Codable, Equatable, Sendable {
    var formatVersion: Int
    var projectionVersion: Int
    var maximumChunksPerSource: Int
    var maximumTotalChunks: Int
    var sources: [ChatSemanticIndexSource]
}

nonisolated struct ChatSemanticIndexSource: Codable, Equatable, Sendable {
    let sourceKey: ChatSourceKey
    let fingerprint: String
    let chunks: [ChatRetrievalChunk]
    let vectors: [[Float]?]
    let embeddingProviderID: String
    let embeddingsComplete: Bool
}

nonisolated struct ChatSemanticIndex {
    static let formatVersion = 2

    let fileURL: URL
    var embedder: any ChatEmbeddingProviding
    var maximumChunksPerSource = 100
    var maximumTotalChunks = 50_000

    init(fileURL: URL, embedder: any ChatEmbeddingProviding = NaturalLanguageChatEmbedder()) {
        self.fileURL = fileURL
        self.embedder = embedder
    }

    static func defaultURL(fileManager: FileManager = .default) throws -> URL {
        let root = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                       appropriateFor: nil, create: true)
        return root.appendingPathComponent("gbpDiary", isDirectory: true)
            .appendingPathComponent("ChatSemanticIndex.json")
    }

    func load() -> ChatSemanticIndexSnapshot? {
        guard let data = try? Data(contentsOf: fileURL),
              let snapshot = try? JSONDecoder().decode(ChatSemanticIndexSnapshot.self, from: data),
              snapshot.formatVersion == Self.formatVersion,
              snapshot.projectionVersion == ChatCorpusBuilder.projectionVersion else { return nil }
        return snapshot
    }

    @discardableResult
    func rebuild(documents: [ChatRetrievalDocument]) throws -> ChatSemanticIndexReport {
        let previous = load()
        let oldByKey = Dictionary(uniqueKeysWithValues: (previous?.sources ?? []).map { ($0.sourceKey, $0) })
        let configurationMatches = previous?.maximumChunksPerSource == maximumChunksPerSource
            && previous?.maximumTotalChunks == maximumTotalChunks
        let ordered = documents.sorted {
            if $0.source.kind.rawValue != $1.source.kind.rawValue { return $0.source.kind.rawValue < $1.source.kind.rawValue }
            return $0.id < $1.id
        }
        var sources: [ChatSemanticIndexSource] = []
        var chunkBudget = max(0, maximumTotalChunks)
        var added = 0
        var updated = 0
        var unchanged = 0

        for document in ordered {
            let fingerprint = ChatSourceFingerprint.make(document)
            let chunks = Array(ChatChunker.chunks(document: document)
                .prefix(min(max(0, maximumChunksPerSource), chunkBudget)))
            if configurationMatches, let old = oldByKey[document.id], old.fingerprint == fingerprint,
               old.chunks == chunks, old.embeddingProviderID == embedder.reuseIdentifier,
               (!embedder.isAvailable || old.embeddingsComplete) {
                sources.append(old)
                chunkBudget -= old.chunks.count
                unchanged += 1
                continue
            }
            let vectors = chunks.map { embedder.vector(for: $0.text) }
            let complete = !chunks.isEmpty && vectors.allSatisfy { $0 != nil }
            sources.append(ChatSemanticIndexSource(sourceKey: document.id, fingerprint: fingerprint,
                                                   chunks: chunks, vectors: vectors,
                                                   embeddingProviderID: embedder.reuseIdentifier,
                                                   embeddingsComplete: complete))
            chunkBudget -= chunks.count
            if oldByKey[document.id] == nil { added += 1 } else { updated += 1 }
        }
        let currentIDs = Set(documents.map(\.id))
        let deleted = oldByKey.keys.filter { !currentIDs.contains($0) }.count
        let snapshot = ChatSemanticIndexSnapshot(formatVersion: Self.formatVersion,
                                                  projectionVersion: ChatCorpusBuilder.projectionVersion,
                                                  maximumChunksPerSource: maximumChunksPerSource,
                                                  maximumTotalChunks: maximumTotalChunks,
                                                  sources: sources)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(snapshot).write(to: fileURL, options: .atomic)
        return ChatSemanticIndexReport(added: added, updated: updated, unchanged: unchanged, deleted: deleted)
    }

    func search(query: String, limit: Int = 8,
                ranker: ChatHybridRanker = ChatHybridRanker()) -> [ChatRankedChunk] {
        guard let snapshot = load() else { return [] }
        let indexed = snapshot.sources.flatMap { source in
            source.chunks.enumerated().map { offset, chunk in
                ChatIndexedChunk(chunk: chunk, vector: offset < source.vectors.count ? source.vectors[offset] : nil)
            }
        }
        return ranker.rank(query: query, indexedChunks: indexed, queryVector: embedder.vector(for: query), limit: limit)
    }
}

nonisolated enum ChatSourceFingerprint {
    static func make(_ document: ChatRetrievalDocument) -> String {
        let value = [
            String(ChatCorpusBuilder.projectionVersion), document.source.kind.rawValue,
            document.source.id.uuidString.lowercased(), document.source.title,
            document.source.detail ?? "", document.source.navigationKind.rawValue,
            document.source.navigationID.uuidString.lowercased(), document.markdown, document.summary ?? ""
        ].joined(separator: "\u{1f}")
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(format: "%016llx", hash)
    }
}
