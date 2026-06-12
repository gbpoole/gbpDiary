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

`ContentView` owns a `@State var selectedTab: AppTab` and a `@State var currentDate: Date`. It renders a full-width view per tab. The tab selector is a segmented `Picker` in the macOS toolbar (`.principal` placement). Prev/next day buttons appear in the toolbar only when the Day tab is active.

```
ContentView
  ├── Day tab       → DayView(date:)
  ├── Tasks tab     → TasksView()         [filterable full-width table]
  ├── Week tab      → WeekView(weekOf:)
  ├── Timesheet     → TimesheetView()
  ├── Projects      → ProjectsView()      [filterable full-width table]
  ├── People        → PeopleView()        [filterable full-width table]
  ├── Institutions  → InstitutionsView()  [full-width table]
  ├── Minutes       → MinutesListView()   [filterable full-width table]
  ├── Documents     → DocumentsListView() [filterable full-width table]
  └── Tags          → TagsView()          [computed table of all tags across Projects and People]
```

### Data layer

All persistence is SwiftData. Models live in `gbpDiary/Models/`. The `ModelContainer` is created in `gbpDiaryApp` and injected via `.modelContainer()`.

**Obsidian import** is staged. `tools/obsidian_import_bundle.py` scans a vault read-only and writes a deterministic JSON import bundle with diagnostics. `ObsidianBundleImporter` imports that bundle into SwiftData in dependency order (institutions, people, projects, day records, notes, minutes, documents, tasks, derived meeting entries). Run the app with `--import-obsidian-bundle /path/to/bundle.json` to import; use `-ui-testing` with that flag for an in-memory validation run, and add `--exit-after-import` for CLI smoke tests that should terminate after the import attempt. Attachment file copying from bundle `attachmentRefs` is not yet implemented; references are preserved in document descriptions.

**`AttachmentStorage`** (`gbpDiary/Models/AttachmentStorage.swift`) is a pure domain helper (no SwiftData) that manages the on-disk location for attachment files. On macOS files are copied to `~/Library/Application Support/Attachments/`; on iOS to the app's `Documents/Attachments/`. When iCloud is enabled, uncomment the ubiquity-container block in `attachmentsDirectory` and run a one-time migration.

For images, `AttachmentStorage` also provides a two-version resize system: `capSource(at:)` caps the stored source at 2048 px wide on import; `renderURL(forSourceURL:width:)` returns a versioned path `{uuid}_r{width}.png` that busts Textual's image cache on resize; `resizedImageData(at:targetWidth:)` does the CoreGraphics resize; `renderSteps(forSourceWidth:)` returns the full step list `[200, 400, 600, 800, 1000, 1200, 1600, 2048]` for any source width — upscaling beyond the original image size is allowed. The orphan sweep in `gbpDiaryApp` collects both `fileURL` and `renderURL` so old render files are cleaned up on relaunch.

**Task is the canonical domain object.** Tasks are identity-stable across all views. They do not "belong" to a day via a stored list — they appear in day sections through date predicate queries on `scheduledAt` and `completedAt`.

### Day view architecture

The Day tab renders a `DayPageContent` view with four typed sections. Meetings are the only diary `DayEntry` blocks still used; tasks are anchored directly to a `DayRecord` via `Task.dayRecord`.

```
DayPageContent
  └── ScrollView
        └── VStack
              ├── activitySection     ActivitySection — Focus blocks + Activities + Unspecified entries
              ├── meetingsSection     EntryRowView (kind == .meeting) per DayEntry
              ├── newTasksSection     DiaryTaskRow per Task with dayRecord == thisRecord
              ├── completedTasksSection  CompletedTaskRow for tasks completedAt in day
              ├── documentsSection    DayDocumentRow per Document.dayRecord == thisRecord
              ├── notesSection        DayNoteRow per Note in dayRecord.noteItems (drag-to-reorder)
              └── sidebarSections     (Scheduled + Inbox; hidden when showTaskSections == false)
```

Old `DayEntry(kind:.note)` entries are auto-migrated into `DayRecord.notes` the first time each day is opened (`migrateOldNotes()` called on `.onAppear`). The legacy `DayRecord.notes: String?` field is then migrated into a `Note` item via `migrateDayNote()`, also called on `.onAppear`, and cleared afterward.

### Day view sections (inline and sidebar)

| Section | Location | Filter |
|---------|----------|--------|
| Activity | Inline | `dayRecord.focusBlocks` sorted by `sortOrder`; `TaskTimeEntry` objects for `focusBlock == nil` shown as Unspecified |
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
- `DaySlot`: `allDay | morning | afternoon` — time-of-day slot for a `FocusBlock`; morning = before noon, afternoon = noon and later
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
  focusBlock→ FocusBlock?    (nil = unspecified; no @Relationship)

FocusBlock                   (a primary work block for a day; shown in Activity section)
  duration  : Duration       (explicitly entered total time)
  slot      : DaySlot        (allDay | morning | afternoon; default allDay)
  sortOrder : Int
  task     → Task?           (backed by a task; nil if project-backed)
  project  → Project?        (backed by a project; nil if task-backed)
  dayRecord→ DayRecord?      (owning day)
  activities → [TaskTimeEntry]  nullify ↔ TaskTimeEntry.focusBlock
  displayLabel: String       (task.summary ?? project.name ?? "Focus block")
  netHours: Double           (duration.hoursNormalized − sum of activities)

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
  renderURL     : URL?         (render file for images: {uuid}_r{width}.png; nil for non-images)
  renderWidth   : Int?         (current render pixel width used in inline markdown link)
  sourceImageWidth: Int?       (pixel width of capped source file; used to clamp resize steps)
  document      → Document?   (set when attached to a Document)
  note          → Note?        (set when attached to a Note)

Note
  content   : String         (markdown; edited inline in DayNoteRow)
  sortOrder : Int            (drag-to-reorder within a day)
  tagsJSON  : String         (JSON-encoded [String]; use computed `tags` property)
  dayRecord → DayRecord?     (set when captured from a day's Notes section)
  project   → Project?       (optional; displayed as blue chip above note content)
  minutes   → Minutes?       (set when note is the block-based minutes for a meeting; nullify on note delete)
  attachments → [Attachment]  cascade delete ↔ Attachment.note
```

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

### Task state transitions

All transitions are in `Task` extension methods (`markCompleted()`, `unmarkCompleted()`, `markCancelled()`, `unmarkCancelled()`, `setFollowUp(date:)`, `markFollowUpDone()`, `setDuration(_:)`). Call these methods from views; do not mutate `status`, `completedAt`, `cancelledAt`, or `followUpAt` directly.

Status cycle (via tap on status icon in `TaskRowView` or in the `TasksView` table): `.todo` → `.started` → `.completed` → `.followUpPending` → `.cancelled` → `.todo`. Long-press / context menu provides direct access to cancel, follow-up, and reopen. In `TasksView`, a tapped task stays visible during the cycle (`pendingStatusIds`) and is only removed from the filtered list when filters change.

The full state transition table is in the handoff spec (`/Users/gbpoole/swift_app_handoff_spec.md`, section 3).

### Duration

User input is a string like `"1.5h"`, `"2d"`, `"1w"`. Parse with `Duration.parse(_:)` — returns `nil` on invalid input. Always display with `duration.displayString`. Store `hoursNormalized` for all timesheet arithmetic.

### Meeting entries

When a meeting `DayEntry` is created, `addMeeting()` automatically creates and links a `Minutes` object with `meetingAt` defaulting to the nearest quarter-hour (rounding from `Date()`). Deleting a meeting entry requires confirmation (alert) because it also deletes the linked `Minutes`. The meeting's one-line summary is stored on `Minutes.summary` and edited inline in the diary row. The day-view row shows the time chip and optional duration chip alongside the inline summary. Tapping the pencil icon opens `MinutesDetailView`; within that view a further pencil toolbar button opens `MinutesEditorSheet` for full meta editing (attendees, projects, duration, time).

### Shared UI components

- `Chip(label:color:)` — pill label for project/person/tag/duration metadata. Defined in `TaskRowView.swift`. **Canonical color palette:** projects=`.blue`, people=`.purple`, duration=`.gray`, tags=`.teal`, meeting time=`.blue`, follow-up date=`.orange`/`.red`. Use these colors consistently across all views.
- `FlowLayout` — wrapping HStack-like layout. Defined in `MinutesDetailView.swift`.
- `TaskRowView` — renders a task row. Used in DayView sidebar, TasksView, ProjectDetailView, PersonDetailView. Supports `inlineEditing: Bool`.
- `DiaryTaskRow` — renders a root day-task (Task with dayRecord set) with inline editing, notes sub-area, collapse/expand, and subtask tree.
- `TaskEditorSheet` — full task editing sheet. Accepts `task: Task?` (nil = create new) and `defaultDate: Date`. New tasks default to unscheduled; notes field has a visible rounded border. When editing an existing task, a "Time Log" section shows all `TaskTimeEntry` items with an "Add Entry…" button opening `LogTimeSheet`.
- `EntryRowView` — renders a meeting `DayEntry` with inline summary, minutes notes sub-area, and embedded New Tasks subtree. (Note/task DayEntry kinds are no longer rendered.)
- `DayNoteRow` — renders a single `Note` in the day's Notes section. Shows project chip (`.blue`) and tag chips (`.teal`) above the inline markdown content, with a paperclip button (opens file picker) and pencil `InlineRowEditButton` on the same header row. When the note has attachments, shows a compact strip below the content: for images, shows filename + current width label + ↓↑ resize arrows (disabled at min/max) + eye + xmark; for other kinds, icon + filename + eye + xmark. Images are rendered inline via Textual's `URLAttachmentLoader`; resizing writes a new `{uuid}_r{width}.png` render file and updates the markdown link so Textual reloads from a cache miss. Context menu includes "Paste Image from Clipboard" (macOS only, shown when clipboard has an image). Supports drag-to-reorder. `onEdit: nil` hides the pencil button; `onDelete: nil` hides the Delete context-menu item.
- `NoteEditingArea` — self-contained block-based note editor. Wraps `DayNoteRow` with its own `@FocusState`, `selectedBlockId`, and all keyboard monitors (`DeleteKeyMonitor`, `EscapeKeyMonitor`, `ReturnKeyMonitor`, `ShiftArrowMonitor`, `FocusClearMonitor`). Use when editing a single `Note` in a standalone context (e.g. `MinutesDetailView`). Passes `onEdit: nil` and `onDelete: nil` to `DayNoteRow` so those items are hidden. The delete-monitor action guards against `NSTextView` focus for "selected block" cases to prevent interference when embedded inside `DayPageContent` alongside other NoteEditingArea instances.
- `NoteEditorSheet` — sheet for editing `Note.project` and `Note.tags` (content is always edited inline). Accepts `note: Note`.
- `ActivitySection` — top section in `DayPageContent` showing Focus blocks, their Activities, and any Unspecified time entries. "+" opens `FocusBlockEditorSheet`. Total logged time footer shown when non-empty.
- `FocusBlockRow` — collapsible row for one `FocusBlock`. Shows source icon (folder for project-backed, checkmark for task-backed), duration chip, net unspecified time label, "+" to open `LogTimeSheet`, pencil to edit. Context menu includes delete with alert when activities exist.
- `FocusBlockEditorSheet` — sheet for creating or editing a `FocusBlock`. Segmented picker: Task or Project source. Duration text field with `Duration.parse(_:)` validation.
- `LogTimeSheet` — lightweight sheet for adding a `TaskTimeEntry`. Pre-fillable with `presetTask`, `presetFocusBlock`, `presetDate`. Task picker shown when no preset task.
- `DayTaskSidebar` — collapsible sidebar with Scheduled and Inbox sections for a given day.
- `DaySectionHeader` — reusable section header with title and optional "+" button.
- `CompletedTaskRow` — read-only struck-through task row with completion time; tap opens `TaskEditorSheet`.
- `DayDocumentRow` — document row in the day's Documents section. Shows icon + summary + attachment count chip (gray) + pencil edit button on the first line; `documentDescription` as caption on the second line when non-empty. Requires `onEdit: () -> Void`.
- `TasksView` — filterable macOS Table (or List on iOS) of all tasks. Filter controls in `TasksFilterBar`.
- `MinutesDetailView(minutes:asSheet:)` — detail view for a `Minutes` record; pass `asSheet: true` when presenting as a sheet. Toolbar pencil button opens `MinutesEditorSheet` for full meta editing.
- `DocumentDetailView(document:asSheet:)` — same pattern for `Document`.
- `ProjectDetailView(project:asSheet:)` — same pattern for `Project`. Includes a Notes section showing notes linked to the project.
- `PersonDetailView(person:asSheet:)` — same pattern for `Person`.
- `InstitutionDetailView(institution:asSheet:)` — same pattern for `Institution`.
- `TagsView` — computed table of all unique tags used across `Project.tags` and `Person.tags`. Columns: tag name, project count, people count. Tap a row to open `TagDetailSheet` showing chips for all matching projects and people. No model of its own; derives from `@Query` on `Project` and `Person`.
- All entity list pages (`ProjectsView`, `PeopleView`, `InstitutionsView`, `MinutesListView`, `DocumentsListView`) use the same `VStack { filterBar + Divider + Table }` pattern as `TasksView`: macOS `Table` with tap-to-open-sheet on the primary column, iOS `List`. Each has a filter bar (project or institution picker where relevant).

### macOS-specific: keyboard monitors

Five NSEvent monitor classes live in `gbpDiary/Views/DayTab/KeyboardMonitors.swift`: `DeleteKeyMonitor`, `EscapeKeyMonitor`, `ReturnKeyMonitor`, `ShiftArrowMonitor`, `FocusClearMonitor`. All are `final class @unchecked Sendable` with `start()`/`stop()` lifecycle.

`onKeyPress(.delete)` cannot intercept ⌫ inside a `TextField` because `NSTextField.deleteBackward:` fires inside `interpretKeyEvents:` before SwiftUI's handler runs. `DeleteKeyMonitor` uses `NSEvent.addLocalMonitorForEvents(matching: .keyDown)` to intercept at the event level. It is started/stopped in `.onAppear`/`.onDisappear` of `DayPageContent` (for day-level content) and `NoteEditingArea` (for standalone note editing). The action closure checks whether the focused entry is empty before deleting — use a kind-aware check (`task.summary`, `minutes.summary`, `note.content`, `entry.text`) not a generic `entry.text` check. For "selected block (no text focus)" delete actions, always guard with `!(NSApp.keyWindow?.firstResponder is NSTextView)` to prevent interference with other active `NoteEditingArea` instances.

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

- **Import pipeline remaining work**: live attachment file copying from Obsidian document references, a dedicated UI/CLI progress reporter, and versioned migration strategy for importing into older persistent stores. Dry-run bundle generation and SwiftData upsert are implemented.
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
| `FocusBlock.netHours` = max(0, block.duration.hoursNormalized − sum of activity durations) | Activity section | `gbpDiaryTests/Models/FocusBlockTests.swift` | `focusBlock_netHours_subtractsActivities`, `focusBlock_netHours_clampsToZero` |
| Meeting slot classification: morning = start < noon; afternoon = end ≥ noon; meeting with no duration treated as point in time; spans-noon meeting appears in both slots | Activity section / `MeetingSlotClassifier` | `gbpDiaryTests/Domain/MeetingSlotTests.swift` | `slots_morningOnly_noDuration`, `slots_afternoonOnly_noduration`, `slots_spansNoon_morningStartLongDuration`, `slots_morningOnly_shortDurationEndsBeforeNoon`, `slots_exactlyAtNoon_isAfternoon`, `slots_endsExactlyAtNoon_spansNoon` |
| `Task.setDuration` stores duration; auto-completes todo and started tasks (only when completedAt == nil); does NOT overwrite existing completedAt | Task state transitions | `gbpDiaryTests/Models/TaskStateTransitionTests.swift` | `setDuration_completesTodoTaskAndStoresDuration`, `setDuration_completesStartedTask`, `setDuration_doesNotOverwriteExistingCompletedAt` |
| `Task.loggedHoursNormalized` sums `hoursNormalized` across all `timeEntries`; returns 0 when empty. `Task.loggedDuration` returns nil when no entries, else a Duration in hours | Timesheet / Activity section | `gbpDiaryTests/Models/TaskComputedPropertyTests.swift` | `loggedHoursNormalized_sumsAllTimeEntries`, `loggedHoursNormalized_emptyEntries_returnsZero`, `loggedDuration_returnsNilWhenNoEntries`, `loggedDuration_returnsNonNilWithSummedHours` |
| `Task.needsChevron` is true when the task has children OR a non-empty notes string; false for empty-string notes | UI expand/collapse indicator | `gbpDiaryTests/Models/TaskComputedPropertyTests.swift` | `needsChevron_trueWhenHasChildren`, `needsChevron_trueWhenHasNonEmptyNotes`, `needsChevron_falseWhenNoChildrenOrNotes`, `needsChevron_falseWhenNotesIsEmptyString` |
| `DaySlot.defaultDuration`: allDay=1.0d (7.6h), morning=0.5d (3.8h), afternoon=0.5d (3.8h) | Focus block scheduling | `gbpDiaryTests/Models/ValueTypesTests.swift` | `daySlot_defaultDuration_allDay_isOneDay`, `daySlot_defaultDuration_morning_isHalfDay`, `daySlot_defaultDuration_afternoon_isHalfDay` |
| `notesId(for:)` is its own inverse: `notesId(notesId(x)) == x`; always produces a UUID distinct from the input | Inline notes focus management | `gbpDiaryTests/Models/DayEntryContentTests.swift` | `notesId_isOwnInverse`, `notesId_differFromSourceId` |
| `Task.clearFollowUp()` clears `followUpAt` and reverts `.followUpPending` → `.completed`; no-op on other statuses | Task state transitions | `gbpDiaryTests/Models/TaskStateTransitionTests.swift` | `clearFollowUp_revertsToCompleted`, `clearFollowUp_noOpWhenNotFollowUpPending` |
| Image blocks form a visual group only when consecutive AND sharing the same non-nil `groupId`; nil-groupId images are always standalone rows. Text blocks remain standalone. Groups retain original block indices. | Note block rendering/export | `gbpDiaryTests/Models/ValueTypesTests.swift` | `noteBlock_computeGroups_groupsImagesByExplicitGroupId`, `noteBlock_computeGroups_eachImageIsOwnGroup` |
| `NoteBlock.shiftLeft` — images in same group: swap positions (reorder left); otherwise no-op (nil) — cross-group merging is shift-up/down only | Shift-arrow image UX | `gbpDiaryTests/Models/ValueTypesTests.swift` | `shiftLeft_sameGroup_reordersWithinGroup`, `shiftLeft_differentGroups_returnsNil`, `shiftLeft_standaloneWithStandalone_returnsNil`, `shiftLeft_noImageLeft_returnsNil`, `shiftLeft_atStart_returnsNil` |
| `NoteBlock.shiftRight` — mirror of shiftLeft with right neighbor | Shift-arrow image UX | `gbpDiaryTests/Models/ValueTypesTests.swift` | `shiftRight_sameGroup_reordersWithinGroup`, `shiftRight_differentGroups_returnsNil`, `shiftRight_standaloneWithStandalone_returnsNil`, `shiftRight_noImageRight_returnsNil`, `shiftRight_atEnd_returnsNil` |
| `NoteBlock.shiftUp` — image in group: extract before the group as standalone; standalone with image above: merge into that group; standalone with text above: plain swap; at start with no group: nil | Shift-arrow image UX | `gbpDiaryTests/Models/ValueTypesTests.swift` | `shiftUp_inGroup_extractsBeforeGroup`, `shiftUp_inGroup_firstElement_extractsBeforeGroup`, `shiftUp_standaloneWithGroupedAbove_mergesAtEnd`, `shiftUp_standaloneWithStandaloneAbove_createsGroup`, `shiftUp_standaloneWithTextAbove_swaps`, `shiftUp_atStart_returnsNil` |
| `NoteBlock.shiftDown` — mirror of shiftUp with extraction after group and merging below | Shift-arrow image UX | `gbpDiaryTests/Models/ValueTypesTests.swift` | `shiftDown_inGroup_extractsAfterGroup`, `shiftDown_inGroup_lastElement_extractsAfterGroup`, `shiftDown_standaloneWithGroupedBelow_mergesAtStart`, `shiftDown_standaloneWithStandaloneBelow_createsGroup`, `shiftDown_standaloneWithTextBelow_swaps`, `shiftDown_atEnd_returnsNil` |
| `NoteBlock.cleanupGroupIds` clears `groupId` from images whose group was reduced to a single member; no-op on multi-member groups and nil-groupId images | Note block rendering | `gbpDiaryTests/Models/ValueTypesTests.swift` | `cleanupGroupIds_soleGroupMember_clearsGroupId`, `cleanupGroupIds_multiMemberGroup_preservesGroupId`, `cleanupGroupIds_mixedGroups_onlyClearsLoneMembers`, `cleanupGroupIds_noGroups_noOp` |
| `NoteBlock.init(from decoder:)` backward-compat: missing `groupId` → nil, missing `alignment` → `.center`, missing `textContent` → `""` | Note persistence | `gbpDiaryTests/Models/ValueTypesTests.swift` | `decoder_withGroupId_roundTrips`, `decoder_withoutGroupId_defaultsToNil`, `decoder_withoutAlignment_defaultsToCenter`, `decoder_withoutTextContent_defaultsToEmpty` |
| Obsidian import bundle preserves core relationships and task metadata when upserting into SwiftData | Obsidian import | `gbpDiaryTests/Import/ObsidianBundleImporterTests.swift` | `importBundle_createsRelationshipsAndTaskMetadata` |
| Obsidian import launch arguments require `--import-obsidian-bundle <path>` and support `--exit-after-import` for CLI validation runs | Obsidian import | `gbpDiaryTests/Import/ObsidianBundleImporterTests.swift` | `launchRequest_parsesBundlePathAndExitFlag`, `launchRequest_requiresBundlePath` |

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
