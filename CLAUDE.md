# gbpDiary — CLAUDE.md

## What this project is

A native Mac-first app (SwiftUI + SwiftData) that is a personal work operating system: daily planning, task execution, timesheet reporting, and a lightweight CMS. It replaces an Obsidian prototype. iPhone support is planned but not yet implemented.

The full domain model and business logic spec is at `/Users/gbpoole/swift_app_handoff_spec.md`. That JSON schema is the authoritative source for entity shapes and state transitions.

---

## Building and running

```bash
# Build for macOS (from repo root)
xcodebuild -scheme gbpDiary -destination 'platform=macOS' build

# Open in Xcode
open gbpDiary.xcodeproj
```

The project uses **`PBXFileSystemSynchronizedRootGroup`** (Xcode 16+). This means Xcode **automatically includes all files** found in `gbpDiary/`. Creating or deleting a Swift file on the filesystem is sufficient — no `.pbxproj` editing needed.

Targets: macOS 15.7 · iOS 26 · Swift 6 (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`).

---

## Architecture

### Navigation

The app is an Obsidian-style shell: `WorkspaceView` (`Views/Workspace/`) is a `NavigationSplitView` with a **browse sidebar** (the `WorkspaceCategory` list — Diary, Tasks, Timesheet, Projects, Meetings, People, Institutions, Documents, Content, Images, Tags — plus a "New Note" button pinned to the sidebar bottom) and a **tabbed detail area** (`WorkspaceTabStrip` + the active tab's content).

State lives in `WorkspaceModel` (injected via `.environment` from `gbpDiaryApp`):
- `tabs: [WorkspaceTabState]` — each tab is a **back/forward browsing history** of `WorkspaceTab` destinations, with its own `DiaryState` (so two Diary tabs can be on different dates).
- Selecting a sidebar category calls `navigate(to:)` on the **active** tab (in-place browsing); back/forward buttons walk that tab's history.
- Meetings open in a **new tab** (`openInNewTab(.minutes(id))`); `focusOrOpen(_:)` reuses an existing tab already showing a destination; `reveal(note:)` jumps to the container (day/meeting/project) that holds a note; `closeEntity(_:)` closes tabs referencing a to-be-deleted model.

`WorkspaceTab` is `.diary | .tasks | .projects | .people | .institutions | .meetings | .documents | .content | .images | .tags | .timesheet` plus entity cases `.project/.person/.institution/.minutes/.document/.contentNote(PersistentIdentifier)`. Category tabs render the existing list/tool views (`.content` → `ContentListView`); entity tabs resolve the model via `modelContext.model(for:)` and render its `…DetailView` (in non-sheet mode; `.contentNote` → `ContentNoteDetailView`). `reveal(note:)` sends a content note to its own `.contentNote` tab (checked before the project fallback).

Note: opening Project / Person / Institution / Document detail from their list views still uses `.sheet(item:)` (not yet routed through `WorkspaceModel`); wiring those drilldowns to in-place tab navigation is pending.

### Data layer

All persistence is SwiftData. Models live in `gbpDiary/Models/`. The `ModelContainer` is created in `gbpDiaryApp` and injected via `.modelContainer()`.

**Obsidian import** is staged. `tools/obsidian_import_bundle.py` scans a vault read-only and writes a deterministic JSON import bundle with diagnostics. Notes are emitted as **markdown `content`** with image links rewritten to inline `attachment://<uuid>` refs (`note_markdown_and_attachments`); the legacy per-note `blocks` array is gone. Markdown files in the vault-root **`Notes/`** directory import as **content notes** (`inferred_type == "content"`) — titled `Note`s (title = filename) with an optional resolved `projectId` and no day record. Inferred Dataview inline fields (`[project:: …]`, `(who:: …)`, `(duration:: …)`, etc.) are stripped from note/description content via `strip_inline_fields` so they don't linger as raw text. `ObsidianBundleImporter` imports the bundle into SwiftData in dependency order (institutions, people, projects, day records, notes, minutes, documents, tasks, derived meeting entries), copying note/document attachment files into the app container. If an older bundle still carries `blocks`, `markdownForImportedNote` flattens them to markdown for backward compatibility. Run the app with `--import-obsidian-bundle /path/to/bundle.json`; use `-ui-testing` with that flag for an in-memory validation run, and `--exit-after-import` for CLI smoke tests that terminate after the import attempt.

**`AttachmentStorage`** (`gbpDiary/Models/AttachmentStorage.swift`) is a pure domain helper (no SwiftData) that manages the on-disk location for attachment files. On macOS files are copied to `~/Library/Application Support/Attachments/`; on iOS to the app's `Documents/Attachments/`. When iCloud is enabled, uncomment the ubiquity-container block in `attachmentsDirectory` and run a one-time migration.

`AttachmentStorage` copies files in (`store(from:fileId:)`) and deletes them (`delete(at:)`) — no image resizing. Images are displayed at their stored size by the markdown renderer. The orphan sweep in `gbpDiaryApp` collects `fileURL`s and removes any file in the attachments directory not referenced by an `Attachment`.

**Managed image references.** Note markdown never contains file paths. Images embed as standard CommonMark whose URL uses the `attachment://<uuid>` scheme, e.g. `![Display Name](attachment://<uuid>)` — see `AttachmentRef` (`Models/AttachmentRef.swift`), a pure helper that formats/parses refs and extracts them from markdown. `NotePreviewMarkdown.render(_:resolve:)` rewrites those refs to `file://` URLs before handing markdown to Textual's `StructuredText` (its default loader reads `file://`). `AttachmentUsageScanner` (`Models/AttachmentUsageScanner.swift`) scans all note markdown to find orphaned attachments (referenced nowhere) for the image library.

**Task is the canonical domain object.** Tasks are identity-stable across all views. They do not "belong" to a day via a stored list — they appear in day sections through date predicate queries on `scheduledAt` and `completedAt`.

### Day view architecture

The Day tab renders a `DayPageContent` view with four typed sections. Meetings are the only diary `DayEntry` blocks still used; tasks are anchored directly to a `DayRecord` via `Task.dayRecord`.

```
DayPageContent
  └── ScrollView
        └── VStack
              ├── activitySection     ActivitySection — Focus blocks (morning/afternoon/all-day/evening) + their Activities
              ├── meetingsSection     EntryRowView (kind == .meeting) per DayEntry
              ├── newTasksSection     DiaryTaskRow per Task with dayRecord == thisRecord
              ├── completedTasksSection  CompletedTaskRow for tasks completedAt in day
              ├── documentsSection    DayDocumentRow per Document.dayRecord == thisRecord
              ├── notesSection        MarkdownDocumentEditor per Note in dayRecord.noteItems (drag-to-reorder)
              └── sidebarSections     (Scheduled + Inbox; hidden when showTaskSections == false)
```

Old `DayEntry(kind:.note)` entries are auto-migrated into `DayRecord.notes` the first time each day is opened (`migrateOldNotes()` called on `.onAppear`). The legacy `DayRecord.notes: String?` field is then migrated into a `Note` item via `migrateDayNote()`, also called on `.onAppear`, and cleared afterward.

### Day view sections (inline and sidebar)

| Section | Location | Filter |
|---------|----------|--------|
| Activity | Inline | Focus blocks + standalone (out-of-range) entries interleaved by time; each entry attaches to its containing block or renders standalone (no unspecified). Evening blocks show as Overtime |
| Notes | Inline | `dayRecord.noteItems` sorted by `sortOrder`; reorderable by drag |
| New Tasks | Inline | `task.dayRecord == thisRecord`, parent == nil — **all statuses shown** |
| Completed | Inline | `status == .completed && completedAt` in `[dayStart, dayEnd)`, excluding dayRecord tasks |
| Meetings | Inline | `DayEntry.kind == .meeting` in this DayRecord |
| Documents | Inline | `Document.dayRecord == thisRecord` |
| Scheduled | Sidebar | `scheduledAt` in `[dayStart, dayEnd)` AND status todo/started |
| Inbox | Sidebar | status todo/started AND parent == nil AND project == nil AND assignee == nil |

All use `@Query(sort: \Task.createdAt) var allTasks` filtered in-memory.

---

## Data model

Value types (Codable structs, not `@Model`) in `Models/ValueTypes.swift`:
- `TaskStatus`: `todo | started | completed | cancelled | followUpPending`
- `DayEntryKind`: `note | task | meeting`
- `DaySlot`: `allDay | morning | afternoon | evening` — time-of-day slot for a `FocusBlock`. Morning = before **12:30**, afternoon = 12:30 until an (optional) evening block's flexible start, evening = at/after that start. Evening has no standard capacity (`defaultDuration` = 0) and `isOvertime == true`. Boundaries live in `DaySlotBoundary`/`DaySlotClassifier` (`Domain/DaySlotClassifier.swift`). Focus blocks are user-defined *ranges*; `FocusBlockAssignment.containingBlock` attaches each entry to the block whose range contains its time (evening wins; morning/afternoon fall back to all-day), **without creating blocks**. Entries outside every block render standalone (see Activity section). Evening is additive (coexists with any standard structure) and has no task/project source.
- `DurationUnit`: `h | d | w` (hours / days≈7.6h / weeks≈38h)
- `Duration`: `value + unit + hoursNormalized`. Use `Duration.parse("1.5h")` for user input.
- `SourceContext`: import provenance metadata (not used by UI, preserved for import pipeline)
- `AttachmentKind`: `pdf | image | text | other` — stored in `Attachment.kind`; `text` covers `.txt`, `.md`, `.csv`, `.json`, `.yaml`, etc.

`@Model` entities and their key relationships:

```
Task
  summary  : String          (was `title` in earlier versions)
  notes    : String?         (was `taskDescription` in earlier versions)
  assignee → Person?
  project  → Project?
  originDay→ DayRecord?      (where captured; not the day-view link)
  originMinutes → Minutes?   (set when absorbed into a meeting's New Tasks list)
  meetingTaskSortOrder: Int  (ordering within minutes.newTasks; default 0)
  parent   → Task?
  children → [Task]          cascade delete
  duration : Duration?       (legacy; used as fallback when timeEntries is empty)
  timeEntries → [TaskTimeEntry]  cascade delete ↔ TaskTimeEntry.task
  focusBlocks → [FocusBlock]     nullify ↔ FocusBlock.task
  loggedDuration: Duration?  (computed from timeEntries; nil if no entries)
  NOTE: Task no longer has a `minutes` relationship.

TaskTimeEntry                (a single logged time entry; used in Activity section)
  date      : Date           (calendar day for which time is logged)
  duration  : Duration
  comment   : String?
  sortOrder : Int
  task     → Task?           (no @Relationship — Task side declares the inverse)
  NOTE: no focusBlock relationship — block membership is derived from `date` at the view layer via FocusBlockAssignment.containingBlock, never stored.

FocusBlock                   (a primary work block for a day; shown in Activity section)
  duration  : Duration       (explicitly entered total time / capacity)
  slot      : DaySlot        (allDay | morning | afternoon | evening; default allDay)
  startTime : Date?          (evening block's flexible start; nil otherwise; default 18:00)
  comment   : String?        (optional free-text note, like TaskTimeEntry.comment; shown in the block row + editor)
  sortOrder : Int
  task     → Task?           (backed by a task; nil if project-backed)
  project  → Project?        (backed by a project; nil if task-backed)
  dayRecord→ DayRecord?      (owning day)
  displayLabel: String       (task.summary ?? project.name ?? slot name)
  NOTE: FocusBlock stores no child-entry relationship; its activities are the time-derived entries (FocusBlockAssignment). Net-remaining is a view-level calc — FocusBlockMath.netHours(capacity:loggedHours:) = max(0, capacity − loggedHours) — over those entries + meetings (FocusBlockRow).

DayEntry                     (a single diary block for one day)
  kind      : DayEntryKind   (.note | .task | .meeting)
  text      : String         (note content; unused for task/meeting)
  sortOrder : Int            (display order within the day)
  indentLevel: Int           (0–6; visual indent in 20pt steps)
  task     → Task?           (set when kind == .task)
  minutes  → Minutes?        (set when kind == .meeting)
  dayRecord→ DayRecord?

DayRecord                    (date, notes?: String [legacy], focusTags[])
  entries   → [DayEntry]     (cascade delete; only meeting kind used now)
  tasks     → [Task]         (nullify on delete; "new tasks" for this day)
  documents → [Document]     (nullify on delete)
  noteItems → [Note]         (nullify on delete; replaces legacy notes: String?)
  focusBlocks → [FocusBlock] (cascade delete ↔ FocusBlock.dayRecord)

Project
  stream       : String?         (research/work stream; renamed from `projectType`)
  tagsJSON     : String          (JSON-encoded [String]; use computed `tags` property)
  tags         : [String]        (computed; wraps tagsJSON)
  parent       → Project?
  subprojects  → [Project]   nullify on parent delete; inverse of `parent` declared explicitly
  devTeam      → [Person]    ↔ Person.devProjects
  devLead      → Person?     nullify on delete; UI requires a lead when devTeam is non-empty
  sciTeam      → [Person]    ↔ Person.sciProjects
  sciLead      → Person?     nullify on delete; UI requires a lead when sciTeam is non-empty
  institutions → [Institution] ↔ Institution.projects
  meetings     → [Minutes]   ↔ Minutes.projects
  documents    → [Document]  ↔ Document.projects
  notes        → [Note]      ↔ Note.project
  focusBlocks  → [FocusBlock] nullify ↔ FocusBlock.project

Person
  tagsJSON     : String          (JSON-encoded [String]; use computed `tags` property)
  tags         : [String]        (computed; wraps tagsJSON)
  institution    → Institution?  ↔ Institution.members
  devProjects    → [Project]
  sciProjects    → [Project]
  minutesAttended→ [Minutes]

Institution
  members  → [Person]   ↔ Person.institution
  projects → [Project]

Minutes
  summary   : String?        (one-line summary; editable inline in diary)
  duration  : Duration?      (optional; same h/d/w format as tasks)
  meetingAt : Date           (defaults to nearest quarter-hour when created)
  minutesContent: String?    (legacy plain-text field; migrated into note.blocks on first open; nil afterward)
  note      → Note?          (cascade delete; block-based meeting minutes; created on first open via ensureNoteExists()/onAppear migration)
  newTasks  → [Task]     ↔ Task.originMinutes  (nullify on delete)
  projects  → [Project]  ↔ Project.meetings
  attendees → [Person]   ↔ Person.minutesAttended

Document
  summary             : String?
  documentDescription : String?  (free-text note explaining relevance/contents)
  attachments → [Attachment]  cascade delete ↔ Attachment.document
  projects    → [Project]     ↔ Project.documents
  dayRecord  → DayRecord?     (set when captured from a day's Documents section)

Attachment     (file copied into app container on import via `AttachmentStorage`)
  fileName      : String
  fileURL       : URL          (absolute path within app container — always valid, no resolution needed)
  bookmarkData  : Data?        (unused for new attachments; reserved for migrating pre-existing bookmarked files)
  kind          : AttachmentKind
  mimeType      : String?
  fileSizeBytes : Int?
  displayName          : String?  (user-facing name; used as markdown alt text and in the image library)
  attachmentDescription: String?  (optional longer description of the image's contents/relevance)
  document      → Document?   (set when attached to a Document)
  note          → Note?        (set when attached to a Note)

Note
  title     : String         (free-standing "Content" notes have a non-empty title; day/meeting/legacy project notes leave it "" — see NoteContentMembership)
  content   : String         (markdown, sole source of truth; edited via MarkdownDocumentEditor. Images embed as attachment://<uuid> refs — see AttachmentRef. Note-to-note links embed as [Title](note://<uuid>) — see NoteLinkRef)
  sortOrder : Int            (drag-to-reorder within a day)
  tagsJSON  : String         (JSON-encoded [String]; use computed `tags` property)
  dayRecord → DayRecord?     (set when captured from a day's Notes section)
  project   → Project?       (optional; displayed as blue chip above note content)
  minutes   → Minutes?       (set when note is the block-based minutes for a meeting; nullify on note delete)
  attachments → [Attachment]  cascade delete ↔ Attachment.note
  isContentNote: Bool        (computed; NoteContentMembership.isContentNote — vault membership)
```

**Content notes (the "Content" vault).** A *content note* is any `Note` with a non-empty `title`
that is not a day or meeting note (it may still carry a project). It is a free-standing markdown
note that links to other notes Obsidian-style. Links embed as `[Title](note://<uuid>)` (`NoteLinkRef`,
mirroring `AttachmentRef`); `NoteLinkUsageScanner.backlinks(to:in:)` computes backlinks. Content
notes browse via `ContentListView` (sidebar **Content** category), each opening in a
`.contentNote(id)` tab rendering `ContentNoteDetailView` (minutes-style Title/Tags/Project header +
`MarkdownDocumentEditor` + a "Linked from" panel). New notes are created from the Content list "+"
or the sidebar "New Note" button, both presenting `ContentNoteEditorSheet` (title required), which
then calls `WorkspaceModel.openContentForEditing(_:)`. A content note that also has a project appears
in both the vault and that project's Notes section.

**Diary notes are titled content notes on a day.** A note added from the diary is created with the
same `ContentNoteEditorSheet` (passed a `dayRecord`, reported via `onCreated`) — it gets a title,
tags, and optional project, is attached to the day, and shows in the diary Notes section rather than
the Content list (it has a `dayRecord`, so `isContentNote` is false). Its title shows in the
`MarkdownDocumentEditor` header and is editable via `NoteEditorSheet`.

**Note linking (available in every `MarkdownDocumentEditor`).** Link support is internal to the
editor (via `@Query` + `@Environment(WorkspaceModel.self)`), so diary notes, meeting minutes, task
notes, and content notes all get it. `note://<uuid>` links render as clickable chips in the source
pane (`ImageChipTextEditor`, alongside image chips — link chips are sized to one line height so
inserting/removing one doesn't shift text) and as links in the preview. The insert-link and
edit-link controls open `LinkPickerSheet`, a segmented picker over three target kinds — **Content**
notes and **Diary** notes (tag-filtered; date shown for diary options) and **Meetings**
(project-filtered; date shown). A meeting resolves to its minutes `Note` (created if absent), so all
links are uniformly `note://`; the chip label shows the meeting summary + date. Clicking a chip
opens the edit modal (change target / remove); clicking a preview link calls
`WorkspaceModel.reveal(note:)`, which routes to the content tab, the diary day, or the meeting tab.

Each `@Model` has `@Attribute(.unique) var id: UUID` for stable external identity (used by the import pipeline). SwiftData also assigns its own `persistentModelID`.

---

## Key conventions

### Swift 6 / strict concurrency

All types are implicitly `@MainActor` (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`). Model mutations happen synchronously on the main actor.

**`Swift.Task` does not compile** in this module — the app's `@Model final class Task` shadows the concurrency type and the `Swift.` qualifier does not pierce it. Avoid Swift concurrency tasks entirely where possible. For deferred work on the main thread, prefer `.onChange(of:)` to react to state changes after a render cycle rather than using `DispatchQueue` or async/await.

### Adding new files

Just create the `.swift` file in the right directory — Xcode picks it up automatically. Suggested locations:
- New model → `gbpDiary/Models/`
- New view for an existing tab → `gbpDiary/Views/<TabName>Tab/`
- Shared UI component → `gbpDiary/Views/` (top level of Views)

### Querying

Prefer `@Query` at the top of a view for simple sorts/filters. For dynamic filters (e.g., date changes as user navigates), use `@Query(sort:)` to fetch all and filter in a computed property. Avoid `#Predicate` with enum comparisons until verified — in-memory filtering is fast enough for personal data volumes.

**List-page filtering.** Every list page (`TasksView`, `ProjectsView`, `PeopleView`, `MinutesListView`, `DocumentsListView`) filters through the shared `FilterBar` + `FilterEngine` pattern (`Views/FilterBar.swift`), reusing the FuzzyPickerField filter language. The page builds `[PickerFilter<Model>]` from its queried data (each filter has an `id`, `label`, `chipColor`, `group`, and a `test` closure), holds `@State activeFilterIds: Set<String>`, renders `FilterBar(filters:activeFilterIds:…)`, and computes its filtered list via `FilterEngine.apply(_:filters:activeIds:)`. Semantics: **OR within a group, AND across groups**; a group with no active filter is ignored; empty selection returns everything. `FilterBar` shows one neutral dropdown per group with the chosen values as removable chips, plus "Clear all filters" (`onClearAll`) and an optional `extraRows` slot for non-discrete filters (e.g. `DateRangeFilterRow` on Tasks). `ProjectsView` seeds `activeFilterIds = ["status.active"]` to preserve its hide-completed default. `InstitutionsView` and `TagsView` have no discrete filter dimension and use no `FilterBar`.

### Task state transitions

All transitions are in `Task` extension methods (`markCompleted()`, `unmarkCompleted()`, `markCancelled()`, `unmarkCancelled()`, `setFollowUp(date:)`, `markFollowUpDone()`, `setDuration(_:)`). Call these methods from views; do not mutate `status`, `completedAt`, `cancelledAt`, or `followUpAt` directly.

Status cycle (via tap on status icon in `TaskRowView` or in the `TasksView` table): `.todo` → `.started` → `.completed` → `.followUpPending` → `.cancelled` → `.todo`. Long-press / context menu provides direct access to cancel, follow-up, and reopen. In `TasksView`, a tapped task stays visible during the cycle (`pendingStatusIds`) and is only removed from the filtered list when filters change.

The full state transition table is in the handoff spec (`/Users/gbpoole/swift_app_handoff_spec.md`, section 3).

### Duration

User input is a string like `"1.5h"`, `"2d"`, `"1w"`. Parse with `Duration.parse(_:)` — returns `nil` on invalid input. Always display with `duration.displayString`. Store `hoursNormalized` for all timesheet arithmetic.

### Meeting entries

When a meeting `DayEntry` is created, `addMeeting()` automatically creates and links a `Minutes` object with `meetingAt` defaulting to the nearest quarter-hour (rounding from `Date()`). Deleting a meeting entry requires confirmation (alert) because it also deletes the linked `Minutes`. The meeting's one-line summary is stored on `Minutes.summary`, edited inline in the diary row (tapping the row line edits the summary; it no longer opens the meeting). The **"Minutes" chip** opens the meeting in a **new workspace tab** (`MinutesDetailView`), a single unified editor for both metadata (summary, projects, time, duration, attendees, laid out compactly) and the minutes markdown. `MinutesEditorSheet` remains only for quick new-meeting creation.

**Import a meeting from the macOS Calendar (macOS only).** The diary action-bar meeting button is a menu (`DayActionItem.menuItems`): "Blank meeting" (the existing path) or "From Calendar…". The latter opens `CalendarEventPickerSheet` (`Views/DayTab/`) defaulted to the diary day; selecting an event hands a `CalendarEventDraft` back and opens `MinutesEditorSheet` pre-filled via a `MinutesEditorPrefill` (summary/time/duration/attendees) plus the day's `DayRecord`. Nothing is persisted until the user taps **Add** — `save()` materializes any new attendee People and links the meeting to the day with a `DayEntry`, so cancelling leaves no orphans. **EventKit is confined to `CalendarService`** (`Domain/CalendarService.swift`, `#if os(macOS)`): it requests access via the completion-handler API (not `async`, since `Swift.Task` is shadowed here), reads events across all calendars — which already aggregate Exchange + Gmail/CalDAV accounts registered on the Mac — and maps `EKEvent`s to platform-neutral `CalendarEventDraft`s. The pure, testable mapping/attendee-resolution logic lives in `Domain/CalendarEventImport.swift` (Foundation only; no EventKit/SwiftData): `CalendarEventImport.minutesDraft(from:)` maps title→summary/start→meetingAt/(end−start)→duration, and `AttendeeMatcher.resolve(...)` matches attendees to existing People by email then name (creating the rest). Requires the `com.apple.security.personal-information.calendars` entitlement (`gbpDiary/gbpDiary.entitlements`) and the `NSCalendars*UsageDescription` Info.plist strings.

### Shared UI components

- `Chip(label:color:)` — pill label for project/person/tag/duration metadata. Defined in `TaskRowView.swift`. **Canonical color palette:** projects=`.blue`, people=`.purple`, duration=`.gray`, tags=`.teal`, meeting time=`.blue`, follow-up date=`.orange`/`.red`. Use these colors consistently across all views.
- `FlowLayout` — wrapping HStack-like layout. Defined in `MinutesDetailView.swift`.
- `TaskRowView` — renders a task row. Used in DayView sidebar, TasksView, ProjectDetailView, PersonDetailView. Supports `inlineEditing: Bool`.
- `DiaryTaskRow` — renders a root day-task (Task with dayRecord set) with inline editing, notes sub-area, collapse/expand, and subtask tree.
- `TaskEditorSheet` — full task editing sheet. Accepts `task: Task?` (nil = create new) and `defaultDate: Date`. New tasks default to unscheduled; notes field has a visible rounded border. When editing an existing task, a "Time Log" section shows all `TaskTimeEntry` items with an "Add Entry…" button opening `LogTimeSheet`.
- `EntryRowView` — renders a meeting `DayEntry` with inline summary, minutes notes sub-area, and embedded New Tasks subtree. (Note/task DayEntry kinds are no longer rendered.)
- `MarkdownDocumentEditor` (`Views/Notes/MarkdownDocumentEditor.swift`) — the single editor for a `Note`. Not editing → rendered markdown preview (tap to edit). Editing on a wide layout (Mac/iPad, `horizontalSizeClass != .compact`) → source `TextEditor` and live Textual preview side by side; on a narrow layout (iPhone) → source with an edit/preview segmented toggle. Shows project chip (`.blue`) + tag chips (`.teal`), an insert-image button (file importer; macOS also supports "Paste Image" from clipboard via context menu), an optional pencil (`onEdit` → NoteEditorSheet for project/tags), and a Done control. Image insertion copies the file via `AttachmentStorage`, links an `Attachment` to the note, and inserts `![name](attachment://<uuid>)`. `onEdit`/`onDelete` are optional (hidden when nil); `startInEdit` opens straight into edit mode (used for freshly-added day notes). Atomic image *chips* in the source pane are a planned enhancement — the source is currently plain markdown text.
- `NoteEditorSheet` — sheet for editing `Note.project` and `Note.tags` (content is always edited inline). Accepts `note: Note`.
- `ActivitySection` — top section in `DayPageContent`. Renders focus blocks and standalone (out-of-range) entries interleaved chronologically (`activityItems`); `ActivityEntryRow` is reused for standalone entries at block-indent level. **Block membership is a pure function of each entry's time** — `entries(for:)` and `standaloneEntries` call `FocusBlockAssignment.containingBlock`; nothing is stored, synced, or normalized, so entries move automatically when their time or the blocks change (`FocusBlockRow` receives its entries rather than querying by relationship). No blocks are auto-created; there is no Unspecified group. Footer shows Total and, separately, Overtime (evening logged hours). `FocusBlockRow` context menu has Edit + Delete.
- `FocusBlockEditorSheet` — create/edit a `FocusBlock`. Evening is additive (always addable); when the slot is Evening a start-time picker (default 18:00) sets `startTime`; evening has no capacity.
- `LogTimeSheet` — logs a `TaskTimeEntry`; pre-selects the slot-matching block (12:30 split; evening if present). Blocks without a task/project show just their slot name.
- `FocusBlockRow` — collapsible row for one `FocusBlock`. Shows source icon (folder for project-backed, checkmark for task-backed), slot/duration chip, net remaining time label, "+" to open `LogTimeSheet`, pencil to edit. Context menu includes delete with alert when activities exist.
- `FocusBlockEditorSheet` — sheet for creating or editing a `FocusBlock`. Segmented picker: Task or Project source. Duration text field with `Duration.parse(_:)` validation.
- `LogTimeSheet` — lightweight sheet for adding a `TaskTimeEntry`. Pre-fillable with `presetTask`, `presetFocusBlock`, `presetDate`. Task picker shown when no preset task.
- `DayTaskSidebar` — collapsible sidebar with Scheduled and Inbox sections for a given day.
- `DaySectionHeader` — reusable section header with title and optional "+" button.
- `CompletedTaskRow` — read-only struck-through task row with completion time; tap opens `TaskEditorSheet`.
- `DayDocumentRow` — document row in the day's Documents section. Shows icon + summary + attachment count chip (gray) + pencil edit button on the first line; `documentDescription` as caption on the second line when non-empty. Requires `onEdit: () -> Void`.
- `TasksView` — filterable macOS Table (or List on iOS) of all tasks. Filter controls in `TasksFilterBar`.
- `MinutesDetailView(minutes:asSheet:)` — unified meeting editor (metadata + minutes markdown). Rendered as a workspace tab (`asSheet: false`) or a sheet. Layout: summary title, a compact metadata block (Projects / Time / Duration / Attendees — Duration is preset chips plus an inline content-sized custom chip with lenient parsing), then the `MarkdownDocumentEditor` for the minutes note (auto-created via `ensureNoteExists`).
- `ImageLibraryView` (`Views/ImagesTab/`) — the Images sidebar tab. Tables all image `Attachment`s with thumbnail, display name, description, usage (referencing notes via `AttachmentUsageScanner` / "Document" / "Unused"), and size. Per-row delete enabled only for unused images; "Delete Unused" bulk action; sidebar badge shows the unused count. `ImageDetailSheet` edits display name/description and lists referencing notes as links that call `WorkspaceModel.reveal(note:)`.
- `WorkspaceView` / `WorkspaceModel` / `WorkspaceTabStrip` (`Views/Workspace/`) — the shell: browse sidebar + per-tab back/forward history. See the Navigation section.
- `DocumentDetailView(document:asSheet:)` — same pattern for `Document`.
- `ProjectDetailView(project:asSheet:)` — same pattern for `Project`. Includes a Notes section showing notes linked to the project.
- `PersonDetailView(person:asSheet:)` — same pattern for `Person`.
- `InstitutionDetailView(institution:asSheet:)` — same pattern for `Institution`.
- `TagsView` — computed table of all unique tags used across `Project.tags` and `Person.tags`. Columns: tag name, project count, people count. Tap a row to open `TagDetailSheet` showing chips for all matching projects and people. No model of its own; derives from `@Query` on `Project` and `Person`.
- All entity list pages (`ProjectsView`, `PeopleView`, `InstitutionsView`, `MinutesListView`, `DocumentsListView`) use the same `VStack { filterBar + Divider + Table }` pattern as `TasksView`: macOS `Table` with tap-to-open-sheet on the primary column, iOS `List`. Each has a filter bar (project or institution picker where relevant).

### macOS-specific: keyboard monitors

Five NSEvent monitor classes live in `gbpDiary/Views/DayTab/KeyboardMonitors.swift`: `DeleteKeyMonitor`, `EscapeKeyMonitor`, `ReturnKeyMonitor`, `ShiftArrowMonitor`, `FocusClearMonitor`. All are `final class @unchecked Sendable` with `start()`/`stop()` lifecycle.

`onKeyPress(.delete)` cannot intercept ⌫ inside a `TextField` because `NSTextField.deleteBackward:` fires inside `interpretKeyEvents:` before SwiftUI's handler runs. `DeleteKeyMonitor` uses `NSEvent.addLocalMonitorForEvents(matching: .keyDown)` to intercept at the event level. (The block-note editor that drove these monitors has been replaced by `MarkdownDocumentEditor`, so `DayPageContent` no longer starts them; the monitor classes remain available for any future single-line inline-editing surfaces.)

### macOS SwiftUI quirk: `.alert()` and layout padding

On macOS, applying `.alert()` in the outer modifier chain of a block view (outside `.background()` / `.clipShape()` but alongside `.padding(.horizontal)`) silently collapses the padding's layout proposal, producing ~0pt margin. **Fix:** apply `.alert()` at the `body` level (or inside the inner content chain, before `.background()`), not after the outer layout padding. This does not affect note or task blocks since they use only `.sheet()` or `.contextMenu()` in the outer chain.

### SwiftUI quirk: `LazyVStack` + nested `ScrollView` → infinite layout loop

Do **not** place a view that contains a `ScrollView` inside a `LazyVStack`. `LazyVStack`'s lazy measurement algorithm re-proposes heights as cells scroll into view; if the nested `ScrollView` (or any `NSViewRepresentable` inside it, such as `StructuredText` or `TextEditor`) reports a slightly different size between passes, SwiftUI enters an infinite measure → invalidate → re-measure cycle. Each pass allocates new view descriptors, producing unbounded memory growth and 100 % CPU. **Fix:** use a plain `VStack` instead. For sections bounded in number (e.g., 7 days in `WeekView`) the performance difference is negligible. `DayPageContent` contains a nested `ScrollView`, so any container that holds multiple `DayPageContent` instances must use `VStack`, not `LazyVStack`.

### SwiftUI quirk: Textual `StructuredText` link taps vs. edit-mode gesture

`StructuredText` (Textual package) adds a `SpatialTapGesture` overlay on every text fragment to handle link taps. `.allowsHitTesting(false)` on the `StructuredText` view blocks all events including this overlay — links become unclickable.

When `StructuredText` is used inside a `ZStack` alongside an outer `.simultaneousGesture(TapGesture())` that activates edit mode, the outer gesture callback fires **before** the inner `SpatialTapGesture.onEnded` (which calls `openURL`). Checking a flag synchronously in the outer gesture will always see `false`.

**Fix:** Use a class-based flag (not `@State` — class mutations are immediately visible across closures) and defer the check with `.onChange(of:)`. Example from `EntryNotesSubArea`:

```swift
private final class LinkTapFlags { var didTapLink = false }

@State private var linkFlags = LinkTapFlags()
@State private var tapRequestCount = 0

// On StructuredText:
.environment(\.openURL, OpenURLAction { url in
    linkFlags.didTapLink = true   // class mutation: immediately visible
    openURL(url)
    return .handled
})

// On the outer ZStack:
.simultaneousGesture(TapGesture().onEnded { tapRequestCount += 1 })
.onChange(of: tapRequestCount) {
    if linkFlags.didTapLink {
        linkFlags.didTapLink = false  // link was tapped — suppress edit mode
    } else {
        focusedEntryId.wrappedValue = focusId  // normal tap — activate edit mode
    }
}
```

`.onChange` fires after all synchronous gesture callbacks in the current event cycle, so the flag is set before the check runs.

### Platform guards

Use `#if os(macOS)` for macOS-specific sizing (`.frame(minWidth:minHeight:)` on sheets) and for toolbar item placements. The iOS tab bar and edit button are not yet wired — leave `#if os(iOS)` blocks as stubs.

---

## What is not yet built

- **Edit-mode image chips**: in `MarkdownDocumentEditor`'s source pane, image refs currently show as raw `![…](attachment://…)` markdown. Rendering them as atomic, clickable chips (opening an image edit modal) needs a custom `NSTextView`/`UITextView` and is deferred.
- **Entity-detail-as-tab**: Project / Person / Institution / Document list views still open details via `.sheet(item:)`; route these through `WorkspaceModel` for in-place tab navigation.
- **Import pipeline remaining work**: a dedicated UI/CLI progress reporter and versioned migration strategy for importing into older persistent stores. Bundle generation (markdown notes + `attachment://` refs) and SwiftData upsert with attachment file copying are implemented.
- **Tasks dashboard**: tasks grouped by person + project with age/data-quality diagnostics.
- **iCloud sync**: add `cloudKitContainerIdentifier` to `ModelConfiguration` when ready.
- **iPhone UI**: Day screen as home with fast capture loop.
- **Schema migration**: versioned SwiftData migration stages for future model changes.
- **`DayRecord` focusTags**: model has `focusTags` field, not exposed in UI.
- **Timesheet hierarchy validation**: child duration > parent duration warning.
- **Week view drag-to-reorder**: drag-and-drop works per-day in WeekView but reorder logic is independent per day section.

---

## Testing Contract (Required)

### 1) Behavior-change rule
Any change to business behavior MUST include corresponding unit test changes in the same PR.

Business behavior includes:
- model state transitions
- date/range filtering rules
- reorder/indent algorithms
- timesheet aggregation logic
- relationship integrity expectations

### 2) Spec -> Tests Traceability (Required)
Maintain this table and keep it current whenever this file changes behavior rules.

| Rule / Requirement | Source Section | Test File | Test Name(s) |
|---|---|---|---|
| Task markCompleted sets status/completedAt (idempotent — only sets if nil); preserves cancelledAt | Task state transitions | gbpDiaryTests/Models/TaskStateTransitionTests.swift | `markCompleted_setsExpectedFields`, `markCompleted_preservesExistingCompletedAt`, `markCompleted_preservesExistingCancelledAt` |
| Task markCancelled sets status/cancelledAt (idempotent — only sets if nil); preserves completedAt; clears followUpAt | Task state transitions | gbpDiaryTests/Models/TaskStateTransitionTests.swift | `markCancelled_setsExpectedFields`, `markCancelled_preservesExistingCancelledAt`, `markCancelled_preservesExistingCompletedAt`, `markCancelled_clearsFollowUpAt` |
| Task unmarkCancelled reopens to todo, clears cancelledAt and followUpAt | Task state transitions | gbpDiaryTests/Models/TaskStateTransitionTests.swift | `unmarkCancelled_reopensTask`, `unmarkCancelled_clearsFollowUpAt` |
| Cycling through all states preserves original timestamps (e.g., completedAt survives completed→followUp→cancelled→todo→completed) | Task state transitions | gbpDiaryTests/Models/TaskStateTransitionTests.swift | `cycling_preservesOriginalCompletedAt` |
| Duration parsing + normalization (`h/d/w`) | Duration | gbpDiaryTests/Models/DurationTests.swift | `parse_validInputs_normalizesHours`, `parse_invalidInputs_returnsNil` |
| Timesheet includes only completed tasks with duration in selected interval | Timesheet | gbpDiaryTests/Domain/TimesheetComputationTests.swift | `tasksInRange_requiresCompletedAtAndDuration` |
| Scheduled filter uses `scheduledAt` in `[dayStart, dayEnd)` and todo/started status | Day view sections | gbpDiaryTests/Domain/DayTaskFilteringTests.swift | `scheduled_requiresTodoOrStartedAndWithinDayBounds`, `scheduled_excludesTasksAlreadyInEntries` |
| Inbox filter: status todo/started, parent == nil, project == nil, assignee == nil | Day view sidebar | gbpDiaryTests/Domain/DayTaskFilteringTests.swift | `inbox_includesUnassignedTopLevelActiveTasks`, `inbox_includesStartedButExcludesOtherStatuses` |
| notesId derives a stable focus ID by bit-complementing all 16 UUID bytes; result is its own inverse and never collides with organic UUIDs | Inline task notes / meeting minutes | gbpDiaryTests/Models/DayEntryContentTests.swift | (tested indirectly via `notesAreaFocusId` usage) |
| `entriesInRange` filters `TaskTimeEntry` objects whose `date` falls within the interval; `totalHours(entries:)` sums their `hoursNormalized` | Timesheet entry-based aggregation | gbpDiaryTests/Domain/TimesheetComputationTests.swift | `entriesInRange_filtersCorrectly`, `totalHours_entries_sumsHours` |
| `FocusBlockMath.netHours(capacity:loggedHours:)` = max(0, capacity − loggedHours); the view sums time-derived entry + meeting hours as `loggedHours` (FocusBlock stores no child-entry relationship) | Activity section | `gbpDiaryTests/Models/FocusBlockTests.swift` | `focusBlockMath_netHours_subtractsLogged`, `focusBlockMath_netHours_clampsToZero` |
| Meeting slot classification: morning = start < 12:30; afternoon = end ≥ 12:30; no-duration meeting is a point in time; spanning-boundary meeting appears in both slots | Activity section / `MeetingSlotClassifier` | `gbpDiaryTests/Domain/MeetingSlotTests.swift` | `slots_morningOnly_noDuration`, `slots_afternoonOnly_noduration`, `slots_spansNoon_morningStartLongDuration`, `slots_morningOnly_shortDurationEndsBeforeNoon`, `slots_before1230_isMorning`, `slots_exactlyAt1230_isAfternoon`, `slots_endsExactlyAt1230_spansBoundary` |
| Entry slot classification: before 12:30 → morning; ≥ 12:30 → afternoon; ≥ evening start → evening only when an evening block exists (flexible start); evening has no capacity and is overtime | Focus blocks / `DaySlotClassifier` | `gbpDiaryTests/Domain/DaySlotClassifierTests.swift` | `before1230_isMorning`, `atOrAfter1230_isAfternoon`, `withoutEveningBlock_lateTimeStaysAfternoon`, `withEveningBlock_afterStartIsEvening`, `flexibleEveningStart_isRespected`, `daySlot_evening_hasNoStandardCapacity_andIsOvertime` |
| `FocusBlockAssignment.containingBlock` attaches an entry to the block whose range contains its time (evening wins; morning/afternoon fall back to all-day), or nil (standalone) when none covers it; never creates blocks | Focus blocks / activity grouping | `gbpDiaryTests/Models/FocusBlockTests.swift` | `containingBlock_matchesSlotByTime`, `containingBlock_fallsBackToAllDay`, `containingBlock_eveningWinsAfterItsStart`, `containingBlock_nilWhenOutOfRange` |
| `Task.setDuration` stores duration; auto-completes todo and started tasks (only when completedAt == nil); does NOT overwrite existing completedAt | Task state transitions | `gbpDiaryTests/Models/TaskStateTransitionTests.swift` | `setDuration_completesTodoTaskAndStoresDuration`, `setDuration_completesStartedTask`, `setDuration_doesNotOverwriteExistingCompletedAt` |
| `Task.loggedHoursNormalized` sums `hoursNormalized` across all `timeEntries`; returns 0 when empty. `Task.loggedDuration` returns nil when no entries, else a Duration in hours | Timesheet / Activity section | `gbpDiaryTests/Models/TaskComputedPropertyTests.swift` | `loggedHoursNormalized_sumsAllTimeEntries`, `loggedHoursNormalized_emptyEntries_returnsZero`, `loggedDuration_returnsNilWhenNoEntries`, `loggedDuration_returnsNonNilWithSummedHours` |
| `Task.needsChevron` is true when the task has children OR a non-empty notes string; false for empty-string notes | UI expand/collapse indicator | `gbpDiaryTests/Models/TaskComputedPropertyTests.swift` | `needsChevron_trueWhenHasChildren`, `needsChevron_trueWhenHasNonEmptyNotes`, `needsChevron_falseWhenNoChildrenOrNotes`, `needsChevron_falseWhenNotesIsEmptyString` |
| `DaySlot.defaultDuration`: allDay=1.0d (7.6h), morning=0.5d (3.8h), afternoon=0.5d (3.8h), evening=0h (overtime container) | Focus block scheduling | `gbpDiaryTests/Models/ValueTypesTests.swift`, `gbpDiaryTests/Domain/DaySlotClassifierTests.swift` | `daySlot_defaultDuration_allDay_isOneDay`, `daySlot_defaultDuration_morning_isHalfDay`, `daySlot_defaultDuration_afternoon_isHalfDay`, `daySlot_evening_hasNoStandardCapacity_andIsOvertime` |
| `notesId(for:)` is its own inverse: `notesId(notesId(x)) == x`; always produces a UUID distinct from the input | Inline notes focus management | `gbpDiaryTests/Models/DayEntryContentTests.swift` | `notesId_isOwnInverse`, `notesId_differFromSourceId` |
| `Task.clearFollowUp()` clears `followUpAt` and reverts `.followUpPending` → `.completed`; no-op on other statuses | Task state transitions | `gbpDiaryTests/Models/TaskStateTransitionTests.swift` | `clearFollowUp_revertsToCompleted`, `clearFollowUp_noOpWhenNotFollowUpPending` |
| Managed image refs: `AttachmentRef.url(for:)`/`markdown(for:)` produce `attachment://<uuid>` refs; `id(fromURL:)` parses them (rejecting other schemes/non-UUIDs); `referencedIDs(in:)` extracts all image-ref ids from markdown in order | Markdown notes / managed images | `gbpDiaryTests/Models/AttachmentRefTests.swift` | `url_and_id_roundTrip`, `id_fromURL_rejectsNonAttachmentSchemes`, `markdown_embedsDisplayNameAndRef`, `markdown_sanitizesClosingBracketInDisplayName`, `referencedIDs_extractsAllInOrder`, `referencedIDs_ignoresPlainLinksAndNonAttachmentImages` |
| `AttachmentUsageScanner.orphanedIDs(candidates:contents:)` returns attachment ids referenced by no note markdown; `referencedIDs(inContents:)` unions refs across contents | Image library / orphan detection | `gbpDiaryTests/Models/AttachmentRefTests.swift` | `orphanedIDs_flagsUnreferencedAttachments`, `referencedIDs_acrossContents_isUnion` |
| Obsidian import bundle preserves core relationships and task metadata when upserting into SwiftData | Obsidian import | `gbpDiaryTests/Import/ObsidianBundleImporterTests.swift` | `importBundle_createsRelationshipsAndTaskMetadata` |
| Vault-root `Notes/` files import as titled content notes (title, resolved project, no day record, `isContentNote`); inferred inline fields are stripped from note content | Obsidian import / content notes | `gbpDiaryTests/Import/ObsidianBundleImporterTests.swift`, `tools/test_obsidian_import_bundle.py` | `importBundle_createsContentNoteWithTitleAndProject`, `test_build_bundle_extracts_entities_relationships_and_tasks` |
| Obsidian import launch arguments require `--import-obsidian-bundle <path>` and support `--exit-after-import` for CLI validation runs | Obsidian import | `gbpDiaryTests/Import/ObsidianBundleImporterTests.swift` | `launchRequest_parsesBundlePathAndExitFlag`, `launchRequest_requiresBundlePath` |
| Workspace tabs are per-tab back/forward histories: `navigate(to:)` pushes (no-op on current), back/forward traverse, navigating after back truncates forward history. `openInNewTab` adds+activates; `focusOrOpen` reuses a tab showing the destination else opens one; `closeTab` reassigns active and recreates a Diary tab when the last closes | Navigation / workspace shell | `gbpDiaryTests/Views/WorkspaceModelTests.swift` | `tabState_navigate_pushesHistoryAndEnablesBack`, `tabState_navigate_toCurrentIsNoOp`, `tabState_backForward_traversesHistory`, `tabState_navigateAfterBack_truncatesForwardHistory`, `openInNewTab_addsAndActivates`, `focusOrOpen_activatesExistingTabShowingDestination`, `focusOrOpen_opensNewTabWhenNoneShowsDestination`, `closeTab_reassignsActive`, `closeTab_lastTab_recreatesDiary` |
| `FilterEngine.apply` filters a collection by active `PickerFilter`s: OR within a group, AND across groups; a group with no active filter is ignored; empty active set (or only unknown ids) returns all items | List-page filtering | `gbpDiaryTests/Domain/FilterEngineTests.swift` | `apply_noActiveFilters_returnsAll`, `apply_orWithinGroup_matchesAnyInGroup`, `apply_andAcrossGroups_requiresBothGroups`, `apply_orWithinAndAndAcross_combined`, `apply_groupWithNoActiveFilter_isIgnored`, `apply_unknownActiveId_isIgnored` |
| Note-link refs: `NoteLinkRef.url(for:)`/`markdown(for:)` produce `note://<uuid>` links; `id(fromURL:)` parses them (rejecting other schemes/non-UUIDs); `referencedIDs(in:)` extracts all note-link ids in order, ignoring images and plain links | Content notes / linking | `gbpDiaryTests/Models/NoteLinkRefTests.swift` | `url_and_id_roundTrip`, `id_fromURL_rejectsNonNoteSchemes`, `markdown_embedsTitleAndRef`, `markdown_sanitizesClosingBracketInTitle`, `referencedIDs_extractsAllInOrder`, `referencedIDs_ignoresImageAndPlainLinks` |
| `NoteLinkUsageScanner.backlinks(to:in:)` returns ids of notes referencing the target (in order), excluding self; empty when none | Content notes / backlinks | `gbpDiaryTests/Models/NoteLinkUsageScannerTests.swift` | `backlinks_findsReferrers`, `backlinks_excludesSelfReference`, `backlinks_emptyWhenNoReferrers` |
| Content-note membership: `NoteContentMembership.isContentNote` is true iff the title is non-empty (after trimming) and the note has neither a day record nor minutes | Content notes / vault membership | `gbpDiaryTests/Models/NoteLinkUsageScannerTests.swift` | `isContentNote_requiresNonEmptyTitle`, `isContentNote_excludesDayAndMeetingNotes` |
| Calendar import mapping: title→summary (trimmed, nil if blank); start→meetingAt (not rounded); (end−start)→Duration(.h) rounded to 2dp; all-day or zero/negative length → nil duration | Calendar import | `gbpDiaryTests/Domain/CalendarEventImportTests.swift` | `minutesDraft_mapsTitleToSummary_trimmed`, `minutesDraft_blankTitle_yieldsNilSummary`, `durationHours_computesEndMinusStart`, `durationHours_zeroOrNegative_yieldsNil`, `durationHours_roundedToTwoDecimals`, `minutesDraft_timedEvent_setsDurationInHours`, `minutesDraft_allDayEvent_yieldsNilDuration`, `minutesDraft_meetingAtEqualsStart_notRounded` |
| Attendee resolution: match by email (case-insensitive) first, then exact name; else create Person(name,email); empty→[]; blank+no-email skipped; duplicates collapse; `excludingEmails` filtered first | Calendar import | `gbpDiaryTests/Domain/AttendeeMatcherTests.swift` | `resolve_matchesByEmailCaseInsensitive`, `resolve_matchesByExactNameWhenNoEmail`, `resolve_emailTakesPrecedenceOverName`, `resolve_noMatch_createsWithNameAndEmail`, `resolve_noMatchNoName_createsWithEmailAsName`, `resolve_emptyAttendees_returnsEmpty`, `resolve_blankNameNoEmail_isSkipped`, `resolve_duplicateAttendees_collapse`, `resolve_excludingEmails_filtersOrganizer` |
| `FuzzyPickerSelection.toggling` adds an item (matched by `id`) when absent and removes it when present; single-select (`maxSelections == 1`) replaces the whole selection, multi-select appends only while under the cap (else unchanged). Shared by item taps and create-on-the-fly (`onCreateItem`) so creating a new item honors single- vs multi-select | Picker selection semantics | `gbpDiaryTests/Views/FuzzyPickerSelectionTests.swift` | `toggling_multiSelect_addsWhenAbsent`, `toggling_multiSelect_removesWhenPresent`, `toggling_multiSelect_atCap_leavesUnchanged`, `toggling_singleSelect_replacesExistingSelection`, `toggling_singleSelect_fromEmpty_selectsItem`, `toggling_singleSelect_removesWhenSameItemPresent` |

When new rules are added to this document, add at least one row linking each rule to test coverage.

### 3) PR checklist (Required)
- [ ] Added/updated tests for all behavior changes
- [ ] Updated Spec -> Tests Traceability table
- [ ] Ran: `xcodebuild -scheme gbpDiary -destination 'platform=macOS' test`
- [ ] Coverage for changed files did not decrease
- [ ] If no tests changed, justification included in PR description

### 4) Refactor-for-testability rule
If behavior cannot be unit tested in place (for example logic embedded in SwiftUI views), extract pure helper/domain logic first, then test it.

### 5) CLAUDE.md update rule
Any update to architecture, rules, filters, or state transitions in this document MUST include:
1. Updated traceability entries
2. Test updates in the same change set
3. A brief note in the PR description listing affected rows

### 6) Coverage policy
- Initial target: at least 80% coverage for model + domain helper code.
- Coverage should ratchet upward over time.
- Do not merge behavior changes that reduce coverage in changed model/domain files unless explicitly approved.
