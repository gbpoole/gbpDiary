import Foundation

// The single, app-wide definition of the VOICE every AI-generated summary uses: second person
// ("you"), simple past tense, neutral and professional, with no greeting / preamble / sign-off /
// markdown. Every summary prompt in the app — email summaries (and the summary lab that reuses their
// instructions), per-project activity reports, and the activity digest — composes its wording from
// this, so tone / tense / grammatical person stay identical across the app.
//
// Bump `version` whenever a rule below changes: it is folded into version-gated summary staleness
// checks (e.g. the email backlog via `EmailSummaryPrompt.promptVersion`) so stored summaries written
// under an older voice auto-refresh.
nonisolated enum AISummaryStyle {
    /// Bump when any rule below changes. Folded into version-gated summary staleness checks.
    static let version = 1

    /// The core voice rules, one per line — callers embed them verbatim.
    static let rules: [String] = [
        "Voice: address the reader as \"you\"; never use the reader's own name, title, or affiliation.",
        "Tense: use the simple past (for example \"you arranged\", \"Suzanne requested\").",
        "Tone: neutral and professional — factual and concise, never chatty.",
        "Format: output only the summary sentence(s) — no greeting, preamble, sign-off, headings, or markdown.",
    ]

    /// The rules as a "• …" block, for appending to a prompt's bulleted instruction list.
    static var directive: String { rules.map { "• \($0)" }.joined(separator: "\n") }

    /// A single-line form for compact rephrasing prompts (per-project / activity digest).
    static let inline =
        "Write in the second person (\"you\") and the simple past tense, in a neutral, professional tone. " +
        "Output only the summary — no greeting, preamble, sign-off, or markdown."
}
