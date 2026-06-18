# Obsidian Vault Migration

This migration is intentionally staged. The first stage is read-only: parse an
Obsidian vault into a deterministic JSON import bundle and diagnostics report.
Only after the bundle is reviewed should the app import it into a backup or
fresh store.

## Dry Run

```bash
python3 tools/obsidian_import_bundle.py /path/to/ObsidianVault --output /tmp/obsidian-import-bundle.json --summary
```

The tool scans markdown files, ignores `.obsidian`, and emits:

- `institutions`
- `people`
- `projects`
- `minutes`
- `documents`
- `notes`
- `dayRecords`
- `focusBlocks`
- `tasks`
- `diagnostics`

IDs are deterministic, based on entity type plus vault-relative source path.
Task IDs additionally include source section, line, normalized text hash, and
occurrence index.

## Rules From The Original JavaScript

- Projects are identified by `type/project` or project folders.
- People are identified by `type/person` or people folders.
- Institutions are identified by `type/institution` or institution folders.
- Meetings/minutes use `Project`, `Date`, `Duration`, `Attendees`, and `Summary`.
- Documents use `Project`, `Description`, `Attachment`, plus wikilinks in `## Contents`.
- Project teams use `DevTeam` and `SciTeam` wikilinks.
- Parent project links use `Parent`.
- Inline task metadata uses Dataview fields like `who::` and `project::`.
- Task checkbox states map as `[ ]` open, `[x]` completed, `[?]` follow-up pending, and `[-]` cancelled.
- Task state/date stamps use `✅ YYYY-MM-DD` for completion, `🚫 YYYY-MM-DD` for cancellation, and `⏳ YYYY-MM-DD` for scheduled dates.
- Task inline fields include `duration::`, `follow_up::`, `followed_up::`, `minutes::`, `who::`, and `project::`.
- Task hashtags are imported as task tags and removed from the task summary.
- Note, diary, and minutes hashtags are copied into metadata tags and preserved in note text.
- Minutes tags are imported onto their linked `Note`; diary tags are imported onto both the day note and `DayRecord.focusTags`.
- Obsidian image embeds in notes (`![[image.png]]` and `![alt](image.png)`) are converted into image blocks with `Attachment` records.
- Note image files are resolved relative to the note, the vault root, or the sibling folder convention `NOTE.md` → `NOTE/image.png`.
- Timesheet entries are completed tasks with `duration::` metadata.
- Dataview/meta-bind code blocks are generated UI and are stripped from imported note bodies.
- Meeting `Outstanding Previous Tasks` sections are derived views, not imported records.

## App Import

The app can import a reviewed bundle at launch:

```bash
gbpDiary --import-obsidian-bundle /path/to/obsidian-import-bundle.json
```

For validation without writing to the live SwiftData store, include `-ui-testing`:

```bash
gbpDiary -ui-testing --import-obsidian-bundle /path/to/obsidian-import-bundle.json --exit-after-import
```

`-ui-testing` makes the app use an in-memory `ModelContainer`, so the import path
can be exercised safely before a live-store run. `--exit-after-import` terminates
the app after the import attempt so the validation can run from a shell.

## Import Order

1. Institutions
2. People
3. Projects
4. Project relationships: parent, teams, institutions
5. Notes, note tags, and note image attachments
6. Minutes and linked `Note`
7. Documents with copied attachments
8. Focus blocks
9. Tasks and task hierarchy
10. Derived meeting `DayEntry` records
11. Diagnostics review

## Diagnostics To Resolve Before Live Import

- `unresolved-link`: a wikilink could not be matched to the expected entity type.
- Missing or invalid dates for meetings/day records.
- Missing attachment files referenced by documents.
- Missing image files referenced by note image embeds.
- Empty task summaries after stripping inline metadata.
- Duplicate source identities.

## Remaining Work

- Review and resolve unacceptable diagnostics before importing into the live store.
- Import into a backup or fresh app store before writing to the live store.
- Copy referenced attachment files into `AttachmentStorage`; currently references
  are preserved in `Document.documentDescription`.
- Add a dedicated progress reporter if import volume grows enough to need one.
