import Foundation

// One parsed node of a task-breakdown outline: a summary plus nested children.
struct OutlineNode: Equatable {
    var summary: String
    var children: [OutlineNode]

    init(summary: String, children: [OutlineNode] = []) {
        self.summary = summary
        self.children = children
    }
}

// Pure parser for the hybrid quick-add: turns pasted/typed indented text into a task subtree. Rules:
//  • leading whitespace = depth — tabs count as one `indentWidth`, spaces are divided by `indentWidth`
//    (4, matching MarkdownFormatting.indentLines);
//  • an optional leading list marker (`- `, `* `, `+ `) is stripped;
//  • blank / whitespace-only lines are ignored;
//  • a depth that jumps more than one level deeper than its parent is clamped to parent+1 (so sloppy
//    indentation still nests sanely rather than being lost).
enum TaskOutlineParser {
    static func parse(_ text: String, indentWidth: Int = 4) -> [OutlineNode] {
        let width = max(1, indentWidth)
        // (depth, summary) for each non-blank line.
        var lines: [(depth: Int, summary: String)] = []
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            let summary = strippedSummary(line)
            guard !summary.isEmpty else { continue }
            lines.append((rawDepth(line, width: width), summary))
        }
        guard !lines.isEmpty else { return [] }

        // Normalise depths so the first line is 0 and no step increases by more than 1.
        var roots: [OutlineNode] = []
        // Stack of (normalisedDepth, path index into the tree). We rebuild via reference-like recursion
        // using an index path; simplest is to keep a stack of mutable node builders.
        final class Builder { var summary: String; var children: [Builder] = []; init(_ s: String) { summary = s } }
        var rootBuilders: [Builder] = []
        var stack: [(depth: Int, node: Builder)] = []

        for (rawD, summary) in lines {
            // Clamp: depth can be at most current-top-depth + 1.
            let maxDepth = (stack.last?.depth ?? -1) + 1
            let depth = min(max(0, rawD), maxDepth)
            // Pop back to the parent level.
            while let top = stack.last, top.depth >= depth { stack.removeLast() }
            let node = Builder(summary)
            if let parent = stack.last?.node {
                parent.children.append(node)
            } else {
                rootBuilders.append(node)
            }
            stack.append((depth, node))
        }

        func materialise(_ b: Builder) -> OutlineNode {
            OutlineNode(summary: b.summary, children: b.children.map(materialise))
        }
        roots = rootBuilders.map(materialise)
        return roots
    }

    /// Number of indentation levels: each leading tab = one level; leading spaces are counted and divided.
    private static func rawDepth(_ line: String, width: Int) -> Int {
        var tabs = 0
        var spaces = 0
        for ch in line {
            if ch == "\t" { tabs += 1 }
            else if ch == " " { spaces += 1 }
            else { break }
        }
        return tabs + spaces / width
    }

    /// Trim indentation + an optional single list marker, returning the summary text (may be empty).
    private static func strippedSummary(_ line: String) -> String {
        var s = line.drop(while: { $0 == " " || $0 == "\t" })
        if let first = s.first, first == "-" || first == "*" || first == "+" {
            let afterMarker = s.dropFirst()
            if afterMarker.first == " " { s = afterMarker.drop(while: { $0 == " " }) }
        }
        return String(s).trimmingCharacters(in: .whitespaces)
    }
}
