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

The app is an Obsidian-style shell: `WorkspaceView` (`Views/Workspace/`) is a `NavigationSplitView` with a **browse sidebar** and a **tabbed detail area** (`WorkspaceTabStrip` + the active tab's content). The sidebar lists the `WorkspaceCategory` cases **grouped into labelled `Section`s** driven by `WorkspaceCategory.sidebarGroups` — **Workspace** (Diary, Tasks, Timesheet, Emails, Chat), **Records** (Projects, Meetings, People, Institutions), **Library** (Documents, Content, Images, Tags) — plus a "New Note" button pinned to the sidebar bottom. Each item's label is `WorkspaceCategory.title` (a display name distinct from `rawValue`, which stays stable as a persistence key); **the `.triage` category displays as "Emails"** (raw value remains `"Triage"`). The tab-strip chip also uses `.title`.

State lives in `WorkspaceModel` (injected via `.environment` from `gbpDiaryApp`):
- `tabs: [WorkspaceTabState]` — each tab is a **back/forward browsing history** of `WorkspaceTab` destinations, with its own `DiaryState` (so two Diary tabs can be on different dates).
- Selecting a sidebar category calls `navigate(to:)` on the **active** tab (in-place browsing); back/forward buttons walk that tab's history.
- Meetings open in a **new tab** (`openInNewTab(.minutes(id))`); `focusOrOpen(_:)` reuses an existing tab already showing a destination; `reveal(note:)` jumps to the container (day/meeting/project) that holds a note; `closeEntity(_:)` closes tabs referencing a to-be-deleted model. **Deleted-model safety:** an entity tab whose model was deleted this session still resolves via `modelContext.model(for:)` as a *tombstone* whose stored-property reads **trap** (SIGTRAP). Both entity-tab read sites — the tab-strip chip label (`WorkspaceTabStrip.describe`) and the tab content router (`WorkspaceView`) — resolve through **`ModelContext.liveModel(_:as:)`** (`Domain/LiveModel.swift`), which returns nil for a model in `deletedModelsArray` (reading `persistentModelID` never faults), so a stale tab shows its fallback label / the `missing` placeholder instead of crashing. **RULE: never read a model's stored properties from a `PersistentIdentifier` via `model(for:)` in a view that can outlive the model — use `liveModel`.**
- **Session persistence.** The workspace (open tabs, each tab's history + destination, the active
  tab, per-tab Diary date/mode, and **every list page's filter/search/sort**) is saved to
  `UserDefaults` and restored at launch. `WorkspaceModel.snapshot(using:)`/`restore(_:using:)` convert
  to/from the Codable `WorkspaceSnapshot` (`Domain/WorkspaceSession.swift`); entity tabs are stored by
  the model's stable `@Attribute(.unique) var id` (UUID) and re-fetched at restore, **dropping any tab
  whose entity was deleted** (empty result keeps the current tabs). `WorkspaceView` calls
  `restore(using:)` once on appear and `save(using:)` on `scenePhase` leaving `.active` +
  `NSApplication.willTerminateNotification`. List-page filter/search/sort now live on the tab
  (`WorkspaceTabState.pageFilter(for:)` → `ListPageFilter`, alongside the existing `TasksFilterState`),
  so they also survive tab switches. Non-Codable `[KeyPathComparator]` sort orders are persisted via a
  stable `(columnID, ascending)` descriptor — each list page declares `[SortColumn<Model>]` and bridges
  through `TableSortPersistence` (`Domain/TableSortPersistence.swift`). Row selection is not persisted.
- **Safari-like tab shortcuts** live in the app's `AppCommands` **"Tabs" menu** (`gbpDiaryApp.swift`, given the shared `WorkspaceModel` + `HotkeySettings`): New Tab `newTab()` (default **⌘N** — `AppCommands` replaces the default File ▸ New Window via `CommandGroup(replacing: .newItem) { }` so ⌘N opens an in-app tab instead of a new window; native window-tabbing is also disabled with `NSWindow.allowsAutomaticWindowTabbing = false`), Show Next/Previous Tab `selectNextTab()`/`selectPreviousTab()` (defaults **⌘⇧]**/**⌘⇧[**, both wrap around), Show Last Tab `selectLastTab()` (default **⌘9**), Return to Previous Tab `returnToPreviousTab()` (default **⌘⌥[**), and **fixed** position jumps **⌘1…⌘8** `selectTab(at: n-1)` (0-based; out-of-range no-op). `activeIndex` is the active tab's position in `tabs`. **Recency vs. position.** Beyond the *positional* Next/Previous (`⌘⇧]`/`⌘⇧[`), `returnToPreviousTab()` walks a **most-recently-used back-stack** (`recentTabs`, most-recent first): every tab activation funnels through the private `setActive(_:record:)`, which pushes the tab being left (deduped, capped to `tabs.count`, never a tab that no longer exists). Pressing Return-to-Previous **progressively** retraces the chain (open A→B→C, then back → B → A); it passes `record: false` so the tab it leaves isn't re-pushed. **Closing the active tab** (`closeTab`) uses the same back-stack: it falls back to the tab this one was *opened from* (the most-recently-active existing tab), only using the positional neighbour when there's no recency history. `recentTabs` is session-only (not in `WorkspaceSnapshot`; cleared on `restore` and when a tab closes). **Close Tab** `closeActiveTab()` (default **⌘W**; recreates a Diary tab if it was the last, via `closeTab`) is **not** a menu shortcut — a menu ⌘W collides with the standard File ▸ Close and the window-close wins. Instead `CloseTabKeyMonitor` (`KeyboardMonitors.swift`, started by `WorkspaceView`) intercepts the configured Close-Tab hotkey at the `NSEvent` level, **scoped to the workspace window** (via a `WindowAccessor`-resolved `NSWindow`); when the key window is the Settings window or a presented sheet, it falls through to the default Close. The "Close Tab" menu item remains (clickable, no key equivalent) for discoverability.
- **Drag-to-reorder tabs.** Tab chips in `WorkspaceTabStrip` are reorderable by mouse drag — each chip is `.draggable(tab.id.uuidString)` and a `.dropDestination(for: String.self)`; dropping onto a chip inserts the dragged tab **before** it (a trailing zone appends to the end), with a leading accent insertion marker while hovering. Drops call `WorkspaceModel.moveTab(id:toIndex:)`, whose pure index math is `TabReorder.move` (`Domain/TabReorder.swift`, mirroring `DayView.reorderNote`). The active tab is unchanged; the new order is part of the persisted session (saved immediately after a reorder and on the usual lifecycle hooks).
- **Configurable hotkeys.** All the above tab shortcuts are user-editable in **Settings ▸ Shortcuts** (`HotkeySettingsView`, tab id `SettingsTab.shortcuts`). Each app hotkey is a `HotkeyAction` case (`Domain/Hotkeys.swift`) carrying a stable id, display title, **section heading**, and `defaultHotkey`; overrides persist as JSON in `UserDefaults` (`HotkeyStore`) and are resolved by the observable `HotkeySettings` (injected via `.environment`, read by `AppCommands` menu shortcuts and the `CloseTabKeyMonitor`). A `Hotkey` (base key + modifier flags) renders to a SwiftUI `.keyboardShortcut` and matches an `NSEvent`; the settings pane records combos with `HotkeyRecorderMonitor` (an NSEvent capture, like the other monitors). **RULE: any existing or future app-specific hotkey MUST be registered as a `HotkeyAction` under an appropriate `section` (never hardcoded), so it appears in Settings ▸ Shortcuts.** (The ⌘1–8 position jumps are intentionally fixed and documented in the pane, not `HotkeyAction`s.)

`WorkspaceTab` is `.diary | .chat | .triage | .tasks | .projects | .people | .institutions | .meetings | .documents | .content | .images | .tags | .timesheet` plus entity cases `.project/.person/.institution/.minutes/.document/.contentNote(PersistentIdentifier)`. Category tabs render the existing list/tool views (`.chat` → `ChatView`, `.triage` → `EmailTriageView`, `.content` → `ContentListView`); the **Emails** sidebar item (`.triage`) carries a `.badge` of the store-wide un-triaged (`unclassified`) email count; entity tabs resolve the model via `modelContext.model(for:)` and render its `…DetailView` (in non-sheet mode; `.contentNote` → `ContentNoteDetailView`). `reveal(note:)` sends a content note to its own `.contentNote` tab (checked before the project fallback).

Note: opening Project / Person / Institution / Document detail from their list views still uses `.sheet(item:)` (not yet routed through `WorkspaceModel`); wiring those drilldowns to in-place tab navigation is pending.

### Data layer

All persistence is SwiftData. Models live in `gbpDiary/Models/`. The `ModelContainer` is created in `gbpDiaryApp` and injected via `.modelContainer()`.

**Obsidian import** is staged and documented in the **`obsidian-import`** skill (`.claude/skills/obsidian-import/SKILL.md`) — the JSON bundle format, `ObsidianBundleImporter`, `tools/obsidian_import_bundle.py`, and the `--import-obsidian-bundle` launch args. Load it before working on the import pipeline.

**`AttachmentStorage`** (`gbpDiary/Models/AttachmentStorage.swift`) is a pure domain helper (no SwiftData) that manages the on-disk location for attachment files. On macOS files are copied to `~/Library/Application Support/Attachments/`; on iOS to the app's `Documents/Attachments/`. When iCloud is enabled, uncomment the ubiquity-container block in `attachmentsDirectory` and run a one-time migration.

`AttachmentStorage` copies files in (`store(from:fileId:)`) and deletes them (`delete(at:)`) — no image resizing. Images are displayed at their stored size by the markdown renderer. The orphan sweep in `gbpDiaryApp` collects `fileURL`s and removes any file in the attachments directory not referenced by an `Attachment`.

**Managed image references.** Note markdown never contains file paths. Images embed as standard CommonMark whose URL uses the `attachment://<uuid>` scheme, e.g. `![Display Name](attachment://<uuid>)` — see `AttachmentRef` (`Models/AttachmentRef.swift`), a pure helper that formats/parses refs and extracts them from markdown. `NotePreviewMarkdown.render(_:resolve:)` rewrites those refs to `file://` URLs before handing markdown to Textual's `StructuredText` (its default loader reads `file://`). `AttachmentUsageScanner` (`Models/AttachmentUsageScanner.swift`) scans all note markdown to find orphaned attachments (referenced nowhere) for the image library.

**Task is the canonical domain object.** Tasks are identity-stable across all views. They do not "belong" to a day via a stored list — they appear in day sections through date predicate queries on `scheduledAt` and `completedAt`.

### Time accounting (canonical — one source of truth)

**All "time spent" aggregation goes through `Domain/TimeLedger.swift`** — the diary Activity total/overtime,
the Timesheet per-project breakdown, and Chat's time report. The rule, once: each **logged activity** (task
time entry, meeting, sent-email time, completed-task legacy `duration`) counts **once** against **its own**
project; each **standard focus block** contributes its **net** = `max(0, capacity − Σ in-block activity
hours)` to the **block's** project (overtime/evening blocks contribute no capacity — only their in-block
activities count, as overtime); weekend work folds to Friday (overtime). So per-project = block-nets +
activities, and it equals the diary's `standardTotal` + `overtime` except when a block is **over-logged**
(then per-project is the more accurate actual). `TimeLedger.compute(blocks:activities:interval:)` returns
`perProject` (+ `distinctWeeks`), `standardTotal` (the diary "Total"), `overtime`, `grandTotal`, and
per-block `blockNet`. `Domain/TimeLedgerProjection.swift` (`@MainActor`) maps `@Model`s → ledger inputs
using `FocusBlockAssignment.containingBlock` (membership) + `WeekendPolicy` (fold), with a task-shaped
`project(tasks:conversations:…)` (Chat/Timesheet) and a diary-shaped `projectDiary(taskEntries:…)` sharing one
code path. **Email time is owned by the `EmailConversation` entity** (the `conversations:` input, not
per-message `EmailMessage`s), attributed to each conversation's project(s) at each entry's date; in the diary
path a day time entry attributes to its `conversation` → else legacy `email` → else its task.
**RULE: never re-implement time aggregation — extend `TimeLedger`/`TimeLedgerProjection` and add a
`TimeLedgerTests` case.** (`FocusBlockRow.netHours` still uses the shared `FocusBlockMath.netHours` primitive
— consistent with the ledger's `blockNet`.)

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
              └── notesSection        MarkdownDocumentEditor per Note in dayRecord.noteItems (drag-to-reorder)
```
The Scheduled/Inbox task lists are **no longer inline** in the day scroll — they moved to the diary's
always-visible right-hand **`DayTaskPanel`** (see Task inbox/triage). `DiaryView` places the day/week
content beside the panel in a macOS `HSplitView` (toggle in the diary bar, persisted via
`AppSettingsStore.taskPanelShown`); on iOS/compact the panel is omitted.

**Weekend handling — the diary is Mon–Fri.** Saturday/Sunday are not their own diary days; `Domain/WeekendPolicy.swift`
(pure, tested) is the single source of truth for how they fold into weekdays:
- **Navigation:** `DiaryView.stepDate` uses `WeekendPolicy.steppedWeekday` (day mode skips Sat/Sun; Fri↔Mon);
  `DiaryState.currentDate`/`goTo` snap through `WeekendPolicy.weekday(for:)` (a weekend date → the next Monday,
  so a `reveal`/deep-link to a weekend opens Monday); `DiaryDayRollover` rolls a tracked day forward to
  `weekday(for: now)`; `WeekView.weekDays` = `WeekendPolicy.weekdays(...)` → **5 columns (Mon–Fri)**.
- **Inbound → Monday** (`WeekendPolicy.forwardRange(for: date)`, `[Sat..<Tue)` on a Monday): received-email
  filters/triage counts in `DayView`, and the `DayTaskBuckets` due/scheduled "today window" — so weekend
  received mail and weekend-scheduled/due tasks surface on Monday (not overdue).
- **Work → Friday overtime** (`WeekendPolicy.workRange(for: date)`, `[Fri..<Mon)` on a Friday): time entries,
  sent emails, and completed-with-duration task activity. `ActivitySection` renders weekend-dated work in one
  collapsible **"Weekend"** group (excluded from Friday's focus-block bucketing) counted in the **Overtime**
  footer total.
- **Logging "now" on the weekend:** `WeekendPolicy.logNowDate(viewedDate:)` (used by `LogTimeSheet` and the
  `DayTaskPanel` quick-add) stamps the current time on the viewed day, **except** when it's actually the
  weekend and you're parked on the green Monday — then it stamps the real weekend `now`, so weekend work
  books to Friday's overtime rather than Monday. On the weekend the diary bar's date label shows the
  **range** the green Monday covers (e.g. "Sat 6 – Monday 8 January 2026"); on weekdays it's the single date.
- Meetings/notes/documents are `DayRecord`-anchored (created only on a weekday), so they need no folding.
  Weekend-scope is confined to the diary; the global Tasks page keeps real-calendar `TaskFlags` semantics.

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
| Scheduled | Task panel | `scheduledAt` in `[dayStart, dayEnd)` AND status todo/started (triaged) — via `DayTaskBuckets` |
| Inbox | Task panel / Tasks-Triage | open, top-level, `needsTriage` — via `DayTaskFiltering.inboxTasks` / `DayTaskBuckets` |

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
  priority : TaskPriority     (none/low/medium/high; computed over `priorityRaw`; `weight` feeds urgency)
  dueAt    : Date?            (deadline — distinct from `scheduledAt` which is when you plan to work it)
  isOverdue/isDueToday       (computed via pure `TaskFlags`)
  dependsOn→ [Task]          (prerequisites; self many-to-many, nullify)
  blocking → [Task]          (inverse of dependsOn — tasks waiting on this one)
  isBlocked/isBlocking       (computed; blocked while any prerequisite is still open → auto-unblocks)
  waitUntil: Date?           (hidden from lists until this date; `isWaiting` computed)
  needsTriage: Bool          (task inbox: stored default false [existing rows migrate as triaged]; `init` sets it true so EVERY new task lands in the inbox until `markReviewed()`. Recurrence-spawned instances inherit false. See Task inbox/triage)
  until    : Date?           (auto-cancelled once past — swept by TaskRecurrenceDriver)
  recurrenceRule: String?    (e.g. "1w"/"2mo"; completing spawns the next instance)
  recurrenceParentID: UUID?  (lineage of a spawned recurring instance)
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
  email    → EmailMessage?   (LEGACY; per-message email time — EmailMessage declares the inverse. New email time is conversation-owned)
  conversation → EmailConversation?  (set when logging time against an email conversation; EmailConversation declares the inverse + cascade)
  NOTE: no focusBlock relationship — block membership is derived from `date` at the view layer via FocusBlockAssignment.containingBlock, never stored.

FocusBlock                   (a primary work block for a day; shown in Activity section)
  duration  : Duration       (explicitly entered total time / capacity)
  slot      : DaySlot        (allDay | morning | afternoon | evening; default allDay)
  startTime : Date?          (evening block's flexible start; nil otherwise; default 18:00)
  comment   : String?        (optional free-text note, like TaskTimeEntry.comment; shown in the block row + editor)
  sortOrder : Int
  task     → Task?           (backs the block; nil only for an evening overtime container)
  project  → Project?        (LEGACY — time is only ever assigned to tasks; the editor no longer creates
                              project-backed blocks, and a one-time launch migration converts existing ones
                              to task-backed. Retained for data safety / reading old rows — do not set it)
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
  email        : String?         (LEGACY; migrated into `emails` on first launch then nil — do not read)
  emailsJSON   : String          (JSON-encoded [String]; default "[]"; use computed `emails`)
  emails       : [String]        (computed; ordered — first is primary; wraps emailsJSON)
  primaryEmail : String?         (computed; emails.first — use this wherever one email is needed)
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
  newTasks  → [Task]     ↔ Task.originMinutes  (nullify on delete; the meeting's action items)
  documents → [Document] ↔ Document.meetings  (attached documents)
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
  displayWidthPercent  : Int?      (manual display width as % of the note width for previews; nil = 100%/fit pane. Original file always kept full-res for export)
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

### Edit-modal style (canonical — follow for every entity editor)

All entity edit modals (`PersonEditorSheet`, `InstitutionEditorSheet`, `ProjectEditorSheet`,
`DocumentEditorSheet`, `TaskEditorSheet`, `NoteEditorSheet`, `ContentNoteEditorSheet`,
`FocusBlockEditorSheet`, `ResolveAttendeeSheet`, …) use one shape. Do **not** use `Form` for new
edit modals. The reference implementations are `PersonEditorSheet` (in `PeopleView.swift`) and
`ResolveAttendeeSheet`.

```swift
NavigationStack {
    ScrollView {
        VStack(alignment: .leading, spacing: 20) {
            GroupBox("Section label") { <control>.frame(maxWidth: .infinity, alignment: .leading) }
            // one GroupBox per field/section
        }
        .padding()
    }
    .navigationTitle(model == nil ? "New X" : "Edit X")
    .toolbar {
        if model != nil {                                  // Delete only when editing an existing entity
            ToolbarItem(placement: .destructiveAction) {
                Button("Delete") { showingDeleteConfirm = true }.buttonStyle(.borderedProminent).tint(.red)
            }
        }
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
            Button(model == nil ? "Add" : "Save") { save() }.disabled(!canSave)
        }
    }
    .alert("Delete X?", isPresented: $showingDeleteConfirm) {
        Button("Delete", role: .destructive) { delete() }
        Button("Cancel", role: .cancel) {}
    } message: { Text("This permanently deletes the X. …") }
}
.onAppear { /* populate @State from the model when editing */ }
#if os(macOS)
.frame(minWidth: 420, minHeight: 360)   // size to the content; wider/taller for busy editors
#endif
```

Rules:
- **Controls:** `TextField(...).textFieldStyle(.roundedBorder)` (never bare/`.plain` — it must read as
  editable). Single relations use `FuzzyPickerField(selectedItem:)`; multi-relations use
  `FuzzyPickerField(selected:)` — **not** SwiftUI `Picker` dropdowns. Give pickers `onCreateItem:` so
  new People/Institutions/Projects/Tags can be created inline.
- **Delete:** every editor of an existing entity has a destructive Delete (confirm alert) whose handler
  is `workspace.closeEntity(model.persistentModelID); modelContext.delete(model); dismiss()` — inject
  `@Environment(WorkspaceModel.self)`. Relationships nullify via the model's inverses.
- **Read-only "detail" browsers are separate from editors.** A read-only view + a pencil-to-edit button
  is the discouraged pattern.

**Row-tap rule (list pages).** Tapping a row goes straight to the useful surface, never a read-only
detail sheet with an Edit button:
- **Light entities** (`Institution`) → open the **editor sheet** directly.
- **Rich entities** (`Project`, `Person`, `Document`) → open the entity **in a workspace tab**
  (`workspace.focusOrOpen(.project(id))` / `.person(id)` / `.document(id)`) — the tab's detail view
  browses related items and edits metadata inline (no pencil). `Minutes` rows open `MinutesDetailView`
  (edit-in-place), which is already one-click. New people are created via the People page "+" button
  (`PersonEditorSheet`), not by opening a row.

### List / Table page style (canonical — follow for every macOS list page)

Every macOS list page (`TasksView`, `ProjectsView`, `PeopleView`, `MinutesListView`,
`DocumentsListView`, `ContentListView`, `InstitutionsView`, `TagsView`, `ImageLibraryView`) uses one
shape, built from shared components. **Do not** hand-roll cell tap gestures, ad-hoc search boxes, or
fixed-width non-sortable columns for new tables. Reference: `TasksView`.

```swift
VStack(spacing: 0) {
    ListToolbar(searchText: $searchText, searchPrompt: "Search …",
                presets: […], filters: […], activeFilterIds: $activeIds, onClearAll: { … })
    bulkBar            // BulkActionBar — entity pages only
    Divider()
    table              // macOS Table(selection:sortOrder:), iOS List
}
```

Rules:
- **Table**: macOS `Table(rows, selection: $selection, sortOrder: $sortOrder)` where `rows` is the
  filtered array `.sorted(using: sortOrder)`. **Every column is header-sortable** (`TableColumn(value:)`)
  and **resizable** via `.width(min:ideal:)` (never bare `.width(N)`); give date/count/status columns a
  sensible `min`. Sort keys for computed columns are **Comparable computed properties on the model**
  (pure, unit-tested) — e.g. `Project.subprojectCount`, `Minutes.attendeeCount` — not per-page
  snapshots (Tasks is the exception: `TaskRow` precomputes urgency). Body chrome:
  `.scrollContentBackground(.hidden)` + `.background(AppTheme.background)`.
- **Selection + open**: native single-click selection keyed by **`Set<UUID>`** (every `@Model` exposes
  `id: UUID` via its `@Attribute(.unique)`, so `Table`'s `Identifiable.id` is that UUID; a row snapshot
  like `TaskRow` likewise uses `UUID`). **Double-click opens** via `.onTableRowDoubleClick { open(rows[$0]) }`
  (`Views/TableInteraction.swift`) — **never** a SwiftUI tap gesture on a cell (it fights NSTableView
  selection). The open destination follows the **Row-tap rule** above.
- **Toolbar**: `ListToolbar<Item>` (`Views/ListToolbar.swift`) — capsule fuzzy search (`FuzzyMatch`),
  optional one-tap `ToolbarPreset` chips, a **Filters ▾** popover of `FilterGroupSelector` rows (only
  when `filters` is non-empty), and an always-present active-filter row. With no `filters`/`extraPopover`
  it collapses to **search-only** (the Light tier: `TagsView`, `ImageLibraryView`, `InstitutionsView`).
- **Bulk actions**: `BulkActionBar` (`Views/BulkActionBar.swift`) — always present, disabled when empty.
  Entity pages provide a confirmed **Delete** (route through `modelContext.delete` +
  `workspace.closeEntity` for tabbed entities); Tasks adds status transitions. Derived tables
  (`TagsView`) have no bulk bar.
- **Selection follows filtering**: `.onChange(of: Set(rows.map(\.id)))` →
  `TableSelectionReconcile.reconcile` (`Domain/TableSelectionReconcile.swift`, generic) drops
  now-hidden selected rows into a `stashedSelection` and restores them when they reappear; the Clear
  button and every bulk action clear the stash.
- **iOS** keeps a single-tap `List` (touch); double-click/monitor is macOS-only.

### Querying

Prefer `@Query` at the top of a view for simple sorts/filters. For dynamic filters (e.g., date changes as user navigates), use `@Query(sort:)` to fetch all and filter in a computed property. Avoid `#Predicate` with enum comparisons until verified — in-memory filtering is fast enough for personal data volumes.

**Tasks page (`TasksView`) specifics.** Beyond the shared FilterBar it adds: a **fuzzy find** search box
(`FuzzyMatch.matches` over summary/project/assignee/tags), **column-header sorting** (macOS `Table`
`sortOrder: [KeyPathComparator<TaskRow>]` — `TaskRow` is a sortable snapshot precomputing urgency;
default = urgency desc), and **multi-select bulk actions** (`Table(selection:)` + a bulk bar / context
menu: Complete / Started / To do / Cancel / Delete). Search + sort order live on the per-tab
`TasksFilterState`.

**Task inbox / triage.** Every newly-created task starts with `Task.needsTriage == true` (set in `init`;
stored default `false` so existing rows migrate as already-triaged, and recurrence-spawned instances
inherit `false`). Such **open, top-level** tasks form the **inbox** and are **hidden from the normal
(Reviewed) Tasks table** until `markReviewed()` clears the flag — forcing a deliberate second look
(add project/priority/dates) and encouraging regular review. `TasksView` has a **view-mode toggle** on the
per-tab `TasksFilterState.viewMode` (`TaskViewMode`: **Reviewed / Triage / Side-by-side**): *Reviewed* is
the existing filterable table scoped to `!(isOpen && needsTriage)` (closed tasks always show — no need to
triage a done task); *Triage* is a `List` of inbox tasks (oldest first) rendered as **`TaskTriageRow`**
(`Views/DayTab/TaskTriageRow.swift` — status + summary, then grouped inline **project / due / scheduled /
priority** setters and a **Reviewed** button; parallels `EmailTriageRow`); *Side-by-side* is a macOS
`HSplitView` of the two, so you triage with the reviewed list in view for context. The **Tasks sidebar
item shows a `.badge`** of the inbox count (`WorkspaceView.taskInboxCount`). The same inbox also surfaces
in the diary's `DayTaskPanel` Inbox bucket. All edits are live via the shared `@Query` store. The hiding
is scoped to the Reviewed table only — the diary New-Tasks section, project/person task lists, etc. are
unchanged.

**List-page filtering.** Every list page (`TasksView`, `ProjectsView`, `PeopleView`, `MinutesListView`, `DocumentsListView`) filters through the shared `FilterBar` + `FilterEngine` pattern (`Views/FilterBar.swift`), reusing the FuzzyPickerField filter language. **`PeopleView`** has three discrete groups — **Institution**, **Project** (dev/sci team membership), **Tag** — and its search box matches **per field** via `PersonSearch.matches` (`Domain/PersonSearch.swift`): the query fuzzy-matches (`FuzzyMatch`) the name, **any** email, the institution name, or any tag individually — not one concatenated string — so a query can't span across fields and every email (not just the primary) is searchable. The page builds `[PickerFilter<Model>]` from its queried data (each filter has an `id`, `label`, `chipColor`, `group`, and a `test` closure), holds `@State activeFilterIds: Set<String>`, renders `FilterBar(filters:activeFilterIds:…)`, and computes its filtered list via `FilterEngine.apply(_:filters:activeIds:)`. Semantics: **OR within a group, AND across groups**; a group with no active filter is ignored; empty selection returns everything. `FilterBar` shows one neutral dropdown per group with the chosen values as removable chips, plus "Clear all filters" (`onClearAll`) and an optional `extraRows` slot for non-discrete filters (e.g. `DateRangeFilterRow` on Tasks). `ProjectsView` seeds `activeFilterIds = ["status.active"]` to preserve its hide-completed default. `InstitutionsView` and `TagsView` have no discrete filter dimension and use no `FilterBar`.

**Tasks-page toolbar (exception).** `TasksView` does **not** render the tall shared `FilterBar`; it uses a compact **`TasksToolbar`** (`Views/TasksTab/TasksToolbar.swift`) over the same `taskFilters`/`FilterEngine`. Layout is one wrapping block: a compact capsule **search** (fuzzy, `FuzzyMatch`), one-tap **`PresetChip`** toggles — **Incomplete · From email · Overdue · Due today · Mine · Others** (each flips a single `activeFilterId`) plus a mutually-exclusive **Today · Week · Month** date trio (each sets `TasksFilterState.datePreset` + `dateRange` from `DateWindow.range`) — a **"Filters ▾"** popover holding the detailed per-field `FilterGroupSelector` rows + `DateRangeFilterRow` (a custom range clears the date preset) + "Clear all filters", and a removable **active-filter chip** row. The Tasks **date filter matches the `createdAt` (captured) date only**. New preset filters live in `taskFilters`: `preset.incomplete` (group "State" → `isOpen`) and `preset.mine`/`preset.others` (group "Assignee" → assignee ==/≠ `AppSettingsStore.myPersonID`, so they OR with the per-person assignee filters). Filter/search/sort state persists per tab on `TasksFilterState` (`activeFilterIds`, `dateRange`, `datePreset`, `searchText`, `sortOrder`); a new tab **defaults to `activeFilterIds = ["preset.incomplete"]`**. The **Active filters** row is always shown (reads "none" when empty). Table columns are **Summary · Project · Status · Pri · Urg · Assignee · Created · Due · Scheduled** (the three trailing date columns each header-sortable via `TaskRow.createdAt`/`dueKey`/`scheduledKey`); the Summary cell carries small glyphs for blocked/waiting/recurring. `TasksToolbar` is a thin wrapper over the shared `ListToolbar` (see the **List / Table page style** section) supplying the Tasks-specific presets + date-range slot; double-click, bulk bar, and selection-follows-filtering use the shared `.onTableRowDoubleClick` / `BulkActionBar` / `TableSelectionReconcile`.

### Task state transitions

All transitions are in `Task` extension methods (`markCompleted()`, `unmarkCompleted()`, `markCancelled()`, `unmarkCancelled()`, `setFollowUp(date:)`, `markFollowUpDone()`, `setDuration(_:)`, `markReviewed()` [clears the inbox `needsTriage` flag]). Call these methods from views; do not mutate `status`, `completedAt`, `cancelledAt`, `followUpAt`, or `needsTriage` directly.

Status is changed via **`TaskStatusMenu`** (`Views/DayTab/TaskStatusMenu.swift`) — clicking the status
icon opens a **menu to jump directly to any state** (To do / Started / Completed / Cancelled, current one
check-marked) plus **Follow up…** (opens `FollowUpDateSheet`; when already pending: change/clear). It is
a reusable control whose *label* is caller-provided (each surface keeps its own icon) and which reuses
the existing transition methods; an optional `onBeforeChange` closure lets `TasksView` keep a changed row
visible (`pendingStatusIds`). Adopted in `TasksView`, `TaskRowView`, `MeetingActionRow`, and the Activity
`ActivityEntryRow` (no more click-to-cycle; the separate follow-up clock buttons were retired).

The full state transition table is in the handoff spec (`/Users/gbpoole/swift_app_handoff_spec.md`, section 3).

### Duration

User input is a string like `"1.5h"`, `"2d"`, `"1w"`. Parse with `Duration.parse(_:)` — returns `nil` on invalid input. Always display with `duration.displayString`. Store `hoursNormalized` for all timesheet arithmetic.

### Meeting entries

When a meeting `DayEntry` is created, `addMeeting()` automatically creates and links a `Minutes` object with `meetingAt` defaulting to the nearest quarter-hour (rounding from `Date()`). Deleting a meeting entry requires confirmation (alert) because it also deletes the linked `Minutes`. The meeting's one-line summary is stored on `Minutes.summary`, edited inline in the diary row (tapping the row line edits the summary; it no longer opens the meeting). The **"Minutes" chip** opens the meeting in a **new workspace tab** (`MinutesDetailView`), a single unified editor for both metadata (summary, projects, time, duration, attendees, laid out compactly) and the minutes markdown. `MinutesEditorSheet` remains only for quick new-meeting creation.

**Import a meeting from the macOS Calendar (macOS only).** Meeting import (EventKit → `CalendarService`, `CalendarEventImport`, `AttendeeMatcher`, the `resolve(granted:)` first-grant gotcha, and the calendars entitlement) is documented in the **`calendar-import`** skill (`.claude/skills/calendar-import/SKILL.md`). Load it before working on calendar/meeting import.

**Day email fetch + triage via Mail.app / AppleScript (macOS only).** Email is **auto-ingested**: a
global invisible `EmailFetchDriver` (placed once in `WorkspaceView`, like `EmailSummaryDriver`) fetches
new **Inbox + Sent** mail every **5 minutes** (and on launch) via `MailScriptService.fetchRange` (one
AppleScript over `MailScriptParsing.script(rangeStart:rangeEnd:)` with datetime bounds). Fetches are
**incremental** — `EmailIngest.fetchBounds(lastFetchedAt:)` scans from just before the last fetch
(`EmailFetchStateStore.lastFetchedAt`, 10-min overlap) to end-of-today, clamped to a 3-day window; first
run uses the full 3 days. New drafts are upserted (`EmailIngest.upsert`, deduped by Mail's integer id).
**Triage is tri-state** (`Domain/EmailTriage.swift`, `EmailTriageState` from two stored bools
`EmailMessage.dismissed`/`accepted`): **unclassified** (new inbox mail — waits in triage), **accepted**
(shown on the diary), **dismissed** (hidden). On ingest, mail matching a
**spam rule** (`Domain/EmailExclude.swift`, `EmailExcludeRule` = a **sender** rule [full address or
domain `x.com`/`@x.com`] or a **subject** rule [subject *contains* the text, e.g. `[lsc-all]`];
case-insensitive, future-only, managed in the Email settings "Spam rules" pane) is dismissed, and
everything else — **sent and received** — is **unclassified** (so **sent mail is actively triaged like
received**: file a project / log time / accept it on the Emails page; it was previously auto-accepted); the
"other party" is auto-linked when the address is a known Person. **Junk-flagged Inbox mail is excluded**:
the fetch emits Mail's per-message `junk mail status` (`MailScriptParsing` → `MailMessageDraft.isJunk`), and
`EmailIngest.upsert` drops new junk and **dismisses any already-stored copy Mail now flags** (a self-heal,
like the mailing-list loopback sweep) — so spam that slipped in before Mail classified it clears itself on
the next fetch. A one-time migration (`migrateTriageOnce`)
accepts pre-existing non-dismissed emails so they stay on the diary. The diary Email section shows
**accepted conversations** with a message on the day (sent + received — `DayEmailThreadRow`), so a
newly-sent email appears there only once its conversation is accepted in triage. The section
also shows a **"N to triage"** hint (this day's unclassified-conversation count); both it and the section-header tray
button open the central **Triage page** (`workspace.focusOrOpen(.triage)`, `EmailTriageView` — described
below), not a day sheet. We piggyback on Mail (which already holds the OAuth-authenticated Gmail/M365
accounts) rather than doing OAuth ourselves — no credentials, no network. The account + Inbox/Sent
mailbox names are configured in a macOS **Settings** pane (Cmd-, → `EmailSettingsView`, pickers
populated live from Mail; persisted to `UserDefaults` via `EmailSettingsStore`) and targeting one
account keeps the query fast (the unified inbox pulls in Gmail's huge All Mail). Metadata is cached as
`EmailMessage` (`Models/EmailMessage.swift`; in the `Schema`; for Sent the "from" stores the
*recipient*), filtered per day by `cal.isDate(email.date, inSameDayAs: date)` and upserted by Mail's
fast per-message integer `id` (`MailScriptParsing.dedupeKey`) — **not** the RFC `message id` header,
which forces a slow per-message fetch. `Domain/MailScriptService.swift` (`@MainActor`)
**Inbox** messages whose sender is one of the account's own addresses (`email addresses of acc`) are
**skipped** — these are emails you sent to a mailing list you're on that looped back to your Inbox; the
**Sent** copy (correct recipient + direction) already represents them. This loopback exclusion is applied
a **second time at ingest against the "Me" person's addresses** (`EmailIngest.upsert` uses
`EmailSelfMatching` over `AppSettingsStore.myPersonID`'s `Person.emails`) — catching identities the Mail
*account* doesn't list (e.g. a work address that CCs a list from a Gmail account): a new received email
from a "Me" address is dropped, and any that slipped in earlier are dismissed (self-heals every fetch as
your addresses change). `MailScriptService.swift` (`@MainActor`)
runs an `NSAppleScript` on a background queue (the Mail `whose date…` query can be slow) and delivers
`MailMessageDraft`s on the main actor (`MainActor.assumeIsolated`; completion-handler, no `Swift.Task`).
The AppleScript source generation and its delimited-output parsing are pure and tested in
`Domain/MailScriptParsing.swift` (`script(forDay:)`, `parseOutput`, `parseNameAddress`, `dedupeKey`).
Requires the `com.apple.security.automation.apple-events` entitlement + `NSAppleEventsUsageDescription`;
first refresh triggers the one-time macOS **Automation** permission prompt (Privacy & Security →
Automation). v1 = manual refresh, envelope metadata only.

**On-device AI email summaries (macOS 26 + Apple Intelligence).** `EmailMessage` gains `summary: String?`
+ `summaryState` (`EmailSummaryState`: pending/done/failed/unavailable). A **global** invisible
`EmailSummaryDriver` (placed once in `WorkspaceView`) `@Query`s non-dismissed `pending` emails and, via
the SwiftUI **`.task` modifier** (the `Task` type is shadowed by the `@Model Task`), summarises them
**one at a time**: `MailScriptService.fetchContent(_:)` reads the body from **local Mail** (transient —
never stored), and `FoundationModelsSummarizer` (`#if canImport(FoundationModels)`, `@available(macOS 26, *)`,
**on-device `SystemLanguageModel.default` only — no Private Cloud Compute, no network**) generates the
summary via `LanguageModelSession` using **guided generation** (`@Generable EmailSummaryOutput`) +
`GenerationOptions(temperature: 0.3, maximumResponseTokens: 90)` for strict, concise, preamble-free
output. The summary is **identity-aware**: `EmailSummaryDriver.makeContext` builds a `SummaryContext`
(pure types in `Domain/EmailSummary.swift`) from the **"Me" Person** (`AppSettingsStore.myPersonID` →
name + emails), the email's resolved other party (`EmailMessage.person`), the **direction**
(sent/received), and a capped **known-people roster** (`EmailSummaryRoster.build`, priority = other
party + the email's project teams, then alphabetical). `EmailSummaryPrompt.build(context:subject:body:)`
injects these so the model refers to the user as "you" (never their name/title/affiliation), uses short
known names, and drops signatures. **Sender/recipient + direction are authoritative from the Mail header**
(`MailScriptParsing.rec` → `sender`/`to recipients`), never inferred from body text; to keep the model's
*evidence* aligned with that header, `EmailQuotedHistory.newestMessage` (`Domain/EmailQuotedHistory.swift`,
pure) **strips trailing quoted reply/forward history** from the body before summarising — cutting at strong
boundaries (`On … wrote:` attributions incl. the wrapped two-line form, `-----Original Message-----` /
`---- Forwarded message ----` dividers, Outlook underscore separators, and quoted `From:/Sent:/To:` header
blocks) so a chain of other authors can't be mis-attributed to the newest message. It is **conservative**:
no recognised boundary (or a body quoted from its first line) returns the body unchanged. Applied inside
`EmailSummaryPrompt.build`, so both production and the Summary Lab get it. **The voice/tense/person is not defined here** — see the shared
`AISummaryStyle` paragraph below; the email prompt only adds email-specific rules. Tuning is
**versioned**: `EmailSummaryPrompt.promptVersion` (= an email base **+ `AISummaryStyle.version`**, so a
shared-style change also refreshes the backlog) is stored on each email
(`EmailMessage.summaryPromptVersion`); `EmailSummaryPlanning.needsSummary` treats a `done` email with a
stale version as needing a refresh, so bumping the prompt auto-re-summarises the backlog.
Pure/testable pieces live in `Domain/EmailSummary.swift` (`EmailSummaryPrompt`, `SummaryContext`,
`EmailSummaryRoster`, `EmailSummaryText.clean`, `EmailSummaryState`, `EmailSummaryPlanning`,
`EmailSummarizing`). Summaries show as a sparkle-marked line on `DayEmailThreadRow`/`EmailReviewRow`
(replacing the subject once ready; subject shown de-emphasised while pending); a **Regenerate summary**
context menu resets `summaryState` to pending. **HARD CONSTRAINT: everything stays on device** — body read from
local Mail, on-device model, local SwiftData; body is never persisted.

**On-device workspace Chat + Email Summary Lab.** The **Chat** sidebar page (`Views/ChatTab/ChatView.swift`)
has two modes. **Database** mode projects the local SwiftData graph into `ChatRetrievalDocument`s
(`ChatCorpusBuilder`): projects, tasks, people, institutions, meetings/minutes, notes, diary days,
documents, non-dismissed email subjects/stored summaries (**never email bodies**), and bounded extracted
text from PDFs plus UTF-8 text/Markdown/CSV/JSON/YAML attachments. `ChatMarkdownNormalizer` strips
retrieval-only markdown syntax while preserving visible labels and paragraph boundaries;
`ChatChunker` produces deterministic bounded chunks. `ChatSemanticIndex` stores a versioned,
rebuildable JSON sidecar under Application Support containing source fingerprints, chunks, and English
`NaturalLanguage.NLEmbedding` vectors; it incrementally reuses unchanged sources and removes stale
ones. A global invisible `ChatIndexDriver` snapshots SwiftData metadata on the main actor and sends
attachment extraction, chunking, embedding, and sidecar I/O to the shared `ChatRetrievalWorker` actor;
it rebuilds on launch/source membership changes so deleted or dismissed content is removed even when
Chat is idle. Source identity is `(kind, UUID)` because UUID uniqueness is per SwiftData model.
`ChatHybridRanker` combines semantic cosine similarity with lexical overlap and falls back to
lexical search when embeddings are unavailable.

**Query-scoped retrieval + synthesis.** Each `ChatRetrievalDocument`/`ChatRetrievalChunk` carries
filterable metadata — `projectNames: [String]` (lowercased) + `sortDate: Date?` — populated by
`ChatCorpusBuilder` from the same models it projects (bumping `projectionVersion` forces a one-time
reindex). `ChatQueryScopeParser.parse(question:knownProjectNames:now:calendar:)`
(`Domain/ChatQueryScope.swift`, pure) reads the **user's** question (not the follow-up-expanded
retrieval query) into a `ChatQueryScope`: requested `kinds` (singular/plural keyword map), the longest
matching known `projectName`, a date `interval`+`intervalLabel` (today/yesterday/this·last week·month,
this year, "past N days/weeks/months", "recent"), `wantsOverview`, and `wantsTimeTotals`. `ChatView`
ranks a **larger candidate set (~40)**, then `ChatScopedRanking.apply` (`Domain/ChatScopedRanking.swift`)
**hard-restricts** to the scope's kind(s)+project and, when an interval is set, keeps in-window chunks
ordered newest-first — **falling back to the unscoped ranking when the filter empties** — before the
prompt takes the top ~10. When the question asks about time, `ChatView` computes it from the **canonical `TimeLedger`** (see the
**Time accounting** section — the same module the diary and Timesheet use, via `TimeLedgerProjection`),
interval-scoped to `scope.interval` (nil = all time); `ChatTimeTotals.from(ledger:projectName:)` filters
to the asked project and `report(...)` renders the answer **deterministically (no model, never degrades)**.
The model never sums. `ChatPromptBuilder.build` (given
`wantsOverview` + the optional `computedTotals` block) instructs a **grouped, condensed summary** (themed
bullets by default, prose on request, grouped **by project** when the material spans several) rather than
a per-source list, and nudges the model to **lead with higher-importance sources**. **Email importance**
(`EmailMessage.importance`, manual H/M/L, Low = neutral) rides the corpus as `importanceWeight` on each
`ChatRetrievalDocument`/`ChatRetrievalChunk`; `ChatImportanceBoost.adjust` applies a mild multiplicative
score boost in `ChatHybridRanker` (High +25% / Medium +12.5% / Low unchanged — it re-orders near-ties, never
resurrects a zero-relevance chunk), and it breaks exact date ties in `ChatScopedRanking`. Medium/High
emails also render an `Importance:` line in their corpus fields (Low omitted). Bumping
`ChatCorpusBuilder.projectionVersion` (now **3**) forces the one-time reindex. A bounded, source-labelled prompt is sent only to
the on-device `SystemLanguageModel.default` through `FoundationModelsChatAnswerer`; guided output is
validated against supplied citation labels. If Apple Intelligence is unavailable, Chat still shows
the locally ranked source links. No networking, external AI API, or Private Cloud Compute is used.

**Deterministic lenses + weekend fidelity.** After scope resolution the pipeline picks a **lens**
(`Domain/ChatLens.swift`, `ChatLensSelector`): **time report** (`wantsTimeTotals`), **activity digest**
(an interval-bounded "what did I do / summarise my …" recap), or the **open box** (retrieval synthesis).
Both lenses are **failure-proof — the app owns every fact and renders the answer itself; the model at most
rephrases app-built text, and if it's unavailable or errors the app's rendering IS the answer** (so a lens
never returns the degraded outcome). The **time-report lens** computes per-project time in-app via
`ChatTimeTotals.compute` (interval-optional — nil = all time; per-project **distinct active weeks** +
hours, deduped by source key) and renders the table deterministically (no model); it then **appends a
per-project "what was done" narrative** — the shared `ProjectActivityReport` (see the per-project reports
paragraph below) rendered as bullets under each project's hours line, still deterministic (no model, no
retrieval). The **activity-digest
lens** (`Domain/ChatActivityDigest.swift`) assembles the window's **real** items (meetings + completed
tasks, projected by `ChatView.activityDigest(for:)`), grouped by weekday, and the model may only rephrase
that block ("add nothing, infer nothing, never mention a day not listed"). **Weekend fold
(`Domain/ChatWeekendFold.swift` over `WeekendPolicy`) is applied to every date entering Chat** — corpus
field text + sort dates (per kind: work→Friday, inbound→Monday) and the time records (work→Friday) — so the
model never sees a Saturday, plus a faithfulness clause in the open-box prompt forbids inferring
days-of-week. Chat had been the one place ignoring `WeekendPolicy`.

**One voice for every AI summary (`Domain/AISummaryStyle.swift`).** All AI-generated *summaries* in the
app share a single, reusable definition of voice — **second person ("you"), simple past tense, neutral
and professional, no greeting/preamble/sign-off/markdown**. `AISummaryStyle` exposes it as `rules`
(lines), `directive` (a `• …` block, appended to a prompt's bulleted instructions) and `inline` (a
one-line form for compact rephrasers), plus a `version` Int. Every summary prompt composes from it:
`EmailSummaryPrompt.instructions` (and the Email Summary Lab, which reuses those instructions),
`ProjectActivityReport.phrasingPrompt`, and `ChatActivityDigestBuilder.phrasingPrompt` — so tone/tense/
person stay identical. **RULE: any new AI summary prompt MUST take its voice from `AISummaryStyle`, never
hardcode tone/tense/person; bump `AISummaryStyle.version` when a rule changes** (it is folded into
`EmailSummaryPrompt.promptVersion`, auto-refreshing the stored email backlog). (This governs *summaries*;
Chat's open-box grounded-answer synthesis and the project-classification prompt are not summaries.)

**Per-project activity reports (time + "what was done"), shared by Timesheet + Chat.** A single pure
report type pairs each project's canonical **time** with a deterministic **narrative** of what was done.
`ChatActivityItem` (`Domain/ChatActivityDigest.swift`) carries `projectNames: [String]` + a
`kind` (`ChatActivityKind`: meeting/completedTask/loggedComment/email) so items group by project.
`ProjectActivityReport`/`ProjectActivitySection` (`Domain/ProjectActivityReport.swift`, pure) hold, per
project, `hours`/`distinctWeeks` + ordered `items`, with `headerLine` (`TimeFormat.hours/days` +
`ChatTimeTotals.weeksText`), `render()` (header + bullets), `narrativeBlock(projectName:)` (bullets only,
optionally scoped — a **named-but-unmatched project returns empty**, nil = all), `section(matching:)`
(case-insensitive), and `phrasingPrompt(section:)` (strict rephrase-only). `ProjectActivityProjection`
(`Domain/ProjectActivityProjection.swift`, `@MainActor`, alongside `TimeLedgerProjection`):
`report(interval:tasks:conversations:meetings:focusBlocks:calendar:maxEmailsPerProject:)` takes hours/weeks
straight from `TimeLedgerProjection.ledger(...)` and gathers narrative items from **four approved sources**
— meetings (`Minutes` → each `meeting.projects`), completed tasks (`Task.completed` + `completedAt` →
`task.project`), logged comments (non-empty `TaskTimeEntry.comment` → `task.project`, non-empty
`FocusBlock.comment` → `project ?? task.project`, and non-empty comments on a conversation's own
`timeEntries` → the conversation's project(s)), and **email conversations** (`EmailConversation` with
projects — one item per conversation, importance-first + capped per project) — each **weekend-folded**
(`ChatWeekendFold.foldWork`),
interval-filtered, project-tagged, carrying a `ChatSourceReference`; sections are projects with hours **or**
items (never the `(no project)` bucket), sorted by hours desc. The **Timesheet** (`TimesheetView`) renders
these as expandable per-project `DisclosureGroup`s: the header keeps the time figures (name · hours · days ·
weeks · percent), the expanded body shows the grouped bullets (Meetings / Completed / Logged notes / Emails,
each tappable to its source) plus a **Summarise ✨** button that generates on-demand on-device prose from
`phrasingPrompt(section:)` via `FoundationModelsChatAnswerer` (rephrase-only, transient, run via a
per-project `.task(id:)`, gated on `answerer.isAvailable`). The Timesheet stays **time-anchored** (only
projects with logged hours). Chat's time-report lens reuses the same report via a `projectActivity` closure
on `ChatAnswerPipeline.run`. **The model never invents — every fact is app-assembled; it only rephrases.**

**Answer orchestration + evaluation harness.** The whole answer sequence (capability check → follow-up
detection → scope resolve → retrieve → `ChatScopedRanking` → **lens** → deterministic report/digest OR
`ChatPromptBuilder` → model call → assembly) lives in **`ChatAnswerPipeline`** (`Domain/ChatAnswerPipeline.swift`),
extracted from the view so it is testable. `ChatView.answerPendingQuestion` is a thin caller that maps the
returned `ChatPipelineResult` (which exposes **every stage** — parsed scope, chosen sources,
`computedTotals`, the assembled `ChatPromptBundle`, and a `ChatPipelineOutcome` of
capability/noResults/unavailable/answered/generationFailed) onto `state.messages`. **Intent resolution is model-driven with a deterministic backstop** (`Domain/ChatQuerySpec.swift`): the
pipeline resolves scope through an injected `ChatScopeResolving`. Production uses
`FoundationModelsScopeResolver` — it asks the on-device model to fill a small `@Generable ChatQuerySpecDraft`
(kinds · project · period · totals/overview flags, resolving references like "that" from recent history),
then **merges that over** the deterministic `HeuristicScopeResolver` (the old `ChatQueryScopeParser` + back-ref
inherit) via the pure `ChatQuerySpecMapping` (validates the project against the known list, whitelists kinds,
maps the period to an interval, **unions** the flags). The merge can only *refine*, never regress, and any
model unavailability returns the heuristic scope unchanged. The harness and unit tests inject
`HeuristicScopeResolver` (or a stub) so scope stays deterministic. The pipeline depends only
on injected abstractions — a `retrieve` closure (production = `ChatRetrievalWorker`), a `ChatAnswering`
(production = `FoundationModelsChatAnswerer`), and a `ChatScopeResolving` — so a **golden-corpus evaluation harness**
(`gbpDiaryTests/Domain/ChatEvalCorpus.swift` + `ChatEvalTests.swift`) runs representative questions end-to-end
over a fixed, frozen-`now` corpus with a **mock answerer**, asserting the deterministic stages (scope,
must-include/exclude sources, exact totals, prompt properties) — the regression signal for every Chat change.
**GUIDING PRINCIPLE (RULE): the on-device model never filters, counts, dates, scopes, or sums — it only
turns a question into intent and writes prose over data the app has already made correct. Any Chat behaviour
change MUST add/adjust a `ChatEvalTests` case.**

**Email Explorer** mode is a session-only summary experiment lab. Its single email selection uses the
shared `FuzzyPickerField`; the body is fetched transiently from Mail, held only in that tab's
`ChatState`, and discarded when the email changes/tab closes. Candidate generation uses
`FoundationModelsEmailSummaryExperimenter`, optional semantically retrieved workspace background,
and a hard prompt boundary: the email is the sole evidence for what it says; background may only
clarify identity/terminology. Lab prompts, bodies, candidates, ratings, and chat messages are not
persisted. **Use this summary** explicitly cleans the candidate and writes it to `EmailMessage.summary`,
sets state `.done`, and records the current production prompt version so the auto-driver does not
immediately replace it. Every physical `WorkspaceTabState` owns an independent `ChatState`; navigating
away/back in that tab preserves it, while session restoration restores only the `.chat` destination
with fresh Database state. **Experiment in Chat** on diary thread, sent-activity, and triage email rows
always creates a new Chat tab in Email Explorer mode for that email; it never reuses another Chat tab.

**Email importance (surface the most important things).** The **`EmailConversation`** entity carries a
**manual** importance (`importanceRaw`/computed `importance: EmailImportance` — H/M/L, **default Low**;
`isImportant` = not Low), mirroring `Task.priorityRaw`/`priority` (per-message `EmailMessage.importance`
still exists but the conversation is authoritative). **Low is the neutral baseline**: no chip, no ranking
boost — only Medium/High carry signal, so unrated mail stays clean. It's set with a one-click
**`EmailImportancePicker`** (M/H toggle cloned from `TaskTriageRow.priorityPicker`; tapping the active level
clears to Low) shown in the triage row, and via a **"Set importance"** context menu on `DayEmailThreadRow`
— both are a **single write on the conversation** (no per-message loop). A read-only **`EmailImportanceChip`**
(Medium/High only; `Views/DayTab/EmailImportanceControls.swift`) shows on the diary thread row. Both the diary
Email section and each Triage day-section **sort importance-first, then by time**. Importance also feeds Chat
(ranking boost + prompt nudge — see the Chat query-scoped retrieval paragraph).

**Managing the day's email (clean / file / connect).** The **cross-cutting management state is owned by the
persistent `EmailConversation` entity** (`Models/EmailConversation.swift`; threaded across days by the reply
graph — see `EmailThreadGraph`/`EmailConversationReconciler`), **not** by individual messages: `dismissed`/
`accepted` (tri-state triage, via `EmailTriageState`), `person: Person?` (the resolved "other party"),
`projects: [Project]`↔`Project.conversations`, `importance`, and its own `timeEntries` (logged time). It's set
**once for the whole conversation** and new mail joins it consistently. `EmailConversation` also exposes the
display helpers that replaced the ephemeral `struct EmailThread` in the views (`latest`, `displaySubject`,
`sentCount`/`receivedCount`, `loggedHours`, `taskCount`/`hasOpenTasks`, `fromName`/`fromAddress`,
`messages(on:)`). Each `EmailMessage` still carries per-message fields (summary, its own `dismissed`/`accepted`
used only for legacy migration, `suggestedProjectID`) and links to its conversation via `EmailMessage.conversation`.
On ingest the reconciler auto-links the conversation's `person` when the sender/recipient address already
belongs to a Person — `EmailPersonMatching.personID(forAddress:in:)` (pure; address-only, case-insensitive);
unmatched → `person == nil`, shown as a yellow "Unrecognized" chip. **The diary Email section is the single
home for the day's mail (sent + received)** — sent emails do **not** render in the Activity section (only their
logged time counts, see below). `DayPageContent` builds a **`DayConversation`** per **accepted** conversation
that has a message on the shown day (the entity + this day's weekend-windowed message slice [received → Monday,
sent → Friday] + this day's logged conversation hours), sorted **importance-first, then latest-first**. Each
renders as a compact **`DayEmailThreadRow`** whose first line is, left to right: a **leading expand control**
(the collapse chevron when the day slice has multiple messages, else a neutral bullet of the same fixed width,
so everything to its right aligns across rows) + an interactive **person chip** (click to reconcile via
`ResolveAttendeeSheet` — sets the conversation's `person` and every message's) + the conversation's project
chips + a **single envelope icon** + the **`N sent · M recv` breakdown** (that day's slice) + to-do +
importance + a trailing **logged-time chip**; the second line is the summary. **Multi-message days expand** to
a **drill-down**: **sent** messages render the full **`SentEmailActivityRow`**, **received** messages a compact
summary/open-in-Mail row. Time is logged against the **conversation** via the row's **"Log time…" context
menu** (→ `LogTimeSheet(presetConversation:)`). Rows sort importance-first.
**Tapping the row opens the day's latest message in Mail.app** — `MailScriptService.openMessage(_:)` resolves
the real mailbox (`EmailSettingsStore`) + account and opens by Mail's integer id via
`MailScriptParsing.openMessageScript`, with a friendly alert if the message can't be opened.

**Whole-thread day summary (synthesized, on-device).** A conversation's day summary is generated on-device
over the member emails' **existing per-email summaries** (app-owned facts — never raw bodies), so it stays
cheap and only rephrases. Pure pieces in `Domain/EmailThreadSummaryPrompt.swift`
(`EmailThreadSummaryPrompt.build`/`instructions` — voice from `AISummaryStyle`; `promptVersion` = base +
`AISummaryStyle.version`; `EmailThreadSummaryFingerprint.make`; `EmailThreadSummaryPlanning.needsSummary`).
It is cached in the `@Model EmailThreadSummary` (`Models/`, in the `Schema`) keyed by `threadKey + dayStart`,
regenerated when membership/inputs change (fingerprint) or the prompt bumps. The global invisible
**`EmailThreadSummaryDriver`** (placed once in `WorkspaceView`, beside `EmailSummaryDriver`) generates them
for multi-message threads whose per-email summaries are all `done`, via
`FoundationModelsSummarizer.summarizeThread(prompt:)`. Views look it up with
`EmailThreadBuilder.summaryText(for:in:)` and fall back to the latest message's per-email summary while
pending / for single-message threads.

**Sent-email time still counts, but sent emails don't render in the Activity section.** The Activity section
shows focus blocks, meetings, and task time — **no email rows**. `ActivitySection` receives the day's
`todayEntries` (task-, email-, and conversation-linked `TaskTimeEntry`s); its plain-entry bucketing keeps
only `email == nil && conversation == nil` entries, while a block's **email/conversation-linked** time is
summed into `emailHours(for:)` and passed to `FocusBlockRow` (as `emailHours: Double`) **only** so it reduces
the block's net remaining (`FocusBlockRow.netHours`) and the day Total/Overtime (via the canonical
`TimeLedger`), consistent with where the emails render (the Email section). The `SentEmailActivityRow` (a
per-message row in the Email section's conversation drill-down) is a **two-line** row: line 1 groups all the
controls together on the
left (open-in-Mail, then an **editable recipient chip** → `ResolveAttendeeSheet` (`resolvePerson` links/creates
a Person and adds the recipient address — **per message**, since a sent message's recipient is specific to it),
an **editable project chip** → `FuzzyPickerField` picker, and the time-log actions), with the send time
trailing on the right. The **project chip and the time-log actions read/write the owning `EmailConversation`**
(the owner of email projects/time), falling back to the message only when unthreaded, so filing here reaches
the conversation-owned report/ledger; **`person` stays per-message**. Line 2 is
the **on-device AI summary** (or the de-emphasised subject until ready — `EmailMessage.isSummarizing`
gates the "summarising…" hint) via the shared `EmailContentLine`. **Quick time-logging:** the one-click
**`1m` / `5m` / `15m`** buttons **accumulate** (each appends a **conversation-linked** task-less `TaskTimeEntry`
at the send time, so the time reaches the canonical ledger / Timesheet / Chat; falls back to a message-linked
entry only if the message is unthreaded) plus an **`⋯`** that opens `LogTimeSheet(presetConversation:)` for
custom values/editing. Email time
chips render in minutes via `TimeFormat.short(hours:)` (`Domain/TimeFormat.swift`) rather than
`Duration.displayString`'s hours. In-block email/conversation time reduces that block's **net remaining**
(`FocusBlockRow.netHours` adds `emailHours`); standalone email time adds to the day total. Email- and
conversation-linked entries are kept out of the plain entry bucketing/rendering (`taskEntries` =
`email == nil && conversation == nil`).

**`EmailTriageView`** (the sidebar **Emails** page; opened from the diary **Email section header's tray
button** or the "N to triage" hint via `workspace.focusOrOpen(.triage)`) is the accept/dismiss workspace.
It shows **every fetched conversation once** (each `EmailConversation` grouped under its latest-message day
into `List` **Sections**, **most-recent day first**; within a day conversations run **earliest → latest**; the
store's rolling ~3-day fetch window bounds it), **segmented into four mutually-exclusive
buckets** (`EmailTriageCategory`: **To triage / Accepted / Tasks / Dismissed**, each with a
store-wide count; default To-triage). **Rows are whole conversations, not individual messages** — each is
bucketed by `EmailTriageCategory.classify(state:hasTasks:)` over the conversation's own `triageState` +
`taskCount` (**unclassified** → **To triage**; else a linked to-do → **Tasks**; else accepted → **Accepted**;
else **Dismissed**). Each `EmailTriageConversationRow`
reads top-to-bottom in the order you parse it: **line 1** = the conversation's **emphasised stripped subject**
(`EmailConversation.displaySubject` — Re:/Fwd: removed, case preserved) + `N sent · M recv` + an **open-in-Mail
envelope** (opens **every** message of the conversation) with the time trailing right; **line 2** = the
**summary** (or "summarising…"); **line 3** = the chips/actions. **Every triage action is a single write on
the conversation** (which owns the state — no per-message loop): the project chip + inline `FuzzyPickerField`
(and tap-to-apply suggestions) set `conversation.projects`; the importance picker sets `conversation.importance`;
the person chip → `ResolveAttendeeSheet` reconciles the other party (sets `conversation.person` + each message's);
the classification icons (Accept ✓ / Dismiss ✕ / move-back-to-triage — only the ones that change the current
state show) sit **after the other icons** and call `conversation.accept()`/`triageDismiss()`/`unclassify()`.
There's also **quick time-logging** — **5m / 15m** capsule chips (like the diary) that append a
conversation-linked `TaskTimeEntry` (`entry.conversation = conversation`), plus a running logged-time chip.
There's a **Refresh** button (incremental fetch-now). The row also has: a **to-do chip** (opens/deletes the
conversation's linked to-dos — `conversation.tasks`), a context menu to **exclude the
sender / domain** (`EmailExcludeStore.add` + `conversation.triageDismiss()`), and a **Make todo** action
(`checklist` icon) that opens `TaskEditorSheet` seeded from the conversation (summary = `displaySubject`,
notes = `latestMessageSummary`, project = the conversation's first) and on create links
`Task.originEmail = conversation.latest` ↔ `EmailMessage.tasks` (deleting the email nullifies the link; the
task survives) and marks the **conversation accepted** (`conversation.accept()`). **Tap-to-apply project
suggestion chips** (never auto-applied): `Domain/EmailProjectSuggestions.swift` (`rank`) combines the other
party's Person projects + projects on **prior same-party conversations** + an **on-device AI pick**
(`conversation.latest.suggestedProjectID`, set by `EmailSummaryDriver` via
`FoundationModelsSummarizer.suggestProjectName`). The email↔to-do link is
**visible both ways**: `TaskEditorSheet` shows a **"From email"** section (sender + subject + Open in
Mail via `MailScriptService.openMessage`), `TaskRowView` shows an **envelope glyph** when
`task.originEmail != nil`, and the diary `DayEmailThreadRow` shows a **to-do marker**
(`checklist`/`checklist.checked` + count, `EmailConversation.taskCount`/`hasOpenTasks`). Incomplete email
to-dos are found via the Tasks page **Source → "From email"** filter combined with the Status filters
(`Task.isOpen` = not completed/cancelled; `EmailMessage.hasTasks`/`hasOpenTask`). Deleting a Person
nullifies both `EmailMessage.person` and `EmailConversation.person`; deleting a Project removes it from a
conversation's `projects` (the conversation + messages survive).

### Shared UI components

- `Chip(label:color:)` — pill label for project/person/tag/duration metadata. Defined in `TaskRowView.swift`. **Canonical color palette:** projects=`.blue`, people=`.purple`, duration=`.gray`, tags=`.teal`, meeting time=`.blue`, follow-up date=`.orange`/`.red`. Use these colors consistently across all views.
- `FlowLayout` — wrapping HStack-like layout. Defined in `MinutesDetailView.swift`.
- `ChatView` (`Views/ChatTab/`) — local semantic database Q&A + per-tab Email Summary Lab. Source chips navigate through `WorkspaceModel`; the email picker is `FuzzyPickerField`; all model generation uses Apple's on-device Foundation Models implementation.
- `TaskRowView` — renders a task row. Used in DayView sidebar, TasksView, ProjectDetailView, PersonDetailView. Supports `inlineEditing: Bool`.
- `DiaryTaskRow` — renders a root day-task (Task with dayRecord set) with inline editing, notes sub-area, collapse/expand, and subtask tree.
- `TaskEditorSheet` — full task editing sheet. Accepts `task: Task?` (nil = create new) and `defaultDate: Date`. New tasks default to unscheduled; notes field has a visible rounded border. When editing an existing task, a "Time Log" section shows all `TaskTimeEntry` items with an "Add Entry…" button opening `LogTimeSheet`.
- `EntryRowView` — renders a meeting `DayEntry` with inline summary, minutes notes sub-area, and embedded New Tasks subtree. (Note/task DayEntry kinds are no longer rendered.)
- `MarkdownDocumentEditor` (`Views/Notes/MarkdownDocumentEditor.swift`) — the single editor for a `Note`. Not editing → rendered markdown preview (tap to edit); an **empty note** (`MarkdownBlank.isBlank` — truly empty *or* only empty list/quote/heading scaffolding like a stray `- `) shows a tall, clearly clickable placeholder instead of a blank-looking render, so empty minutes can always be re-opened for editing. The placeholder shows only when not editing (the live-preview pane stays blank for an empty note). Editing on a wide layout (Mac/iPad, `horizontalSizeClass != .compact`) → source `TextEditor` and live Textual preview side by side; on a narrow layout (iPhone) → source with an edit/preview segmented toggle. Shows project chip (`.blue`) + tag chips (`.teal`), an insert-image button (file importer; macOS also supports "Paste Image" from clipboard via context menu), an optional pencil (`onEdit` → NoteEditorSheet for project/tags), and a Done control. Image insertion copies the file via `AttachmentStorage`, links an `Attachment` to the note, and inserts `![name](attachment://<uuid>)`. `onEdit`/`onDelete` are optional (hidden when nil); `startInEdit` opens straight into edit mode (used for freshly-added day notes). With `showsFormattingToolbar: true` (macOS; enabled for **meeting minutes** via `MinutesDetailView.notesSection`) a **markdown formatting toolbar** appears above the source pane while editing — Bold/Italic/inline-code, H1–H3, bullet/numbered lists, checklist, quote, code block, table — plus keyboard shortcuts (⌘B/⌘I, ⌘⌥1–3, ⌘⇧L/O/U/Q/C/T) handled in `ChipTextView.performKeyEquivalent` (so ⌘B doesn't hit AppKit's font-bold). Each command applies a pure transform from `Domain/MarkdownFormatting.swift` (`FormatCommand` + `apply(_:to:selection:)`) at the text view's selection via the `formatCommand`/`formatToken` pair on `ImageChipTextEditor` — undoable, chips preserved. **Smart list editing** (list, ordered, checkbox, and `>` blockquote lines): **Return** continues the item with the same indentation + marker (bullet char preserved, ordered number incremented, checkbox reset, quote preserved) or ends it when empty (`MarkdownFormatting.returnInList` ← `ChipTextView.insertNewline`); **Tab/Shift-Tab** indent/outdent **any** line (regardless of caret position), quantising leading whitespace to multiples of `indentWidth` (4 spaces) — Tab → next multiple, Shift-Tab → previous (no-op at column 0); the same delta shifts a nested deeper-indented child block with its parent (`indentLines` ← `insertTab`/`insertBacktab`); **Backspace** at a list marker boundary outdents one level or clears the marker (`backspaceInList` ← `deleteBackward`). Editing also enables macOS continuous **spell-checking** (autocorrect/substitutions off so markdown isn't mangled), and **leading/trailing whitespace is trimmed on exit**. Off (default) for diary/task/content notes. Image insertion copies the file via `AttachmentStorage` and inserts `![name](attachment://<uuid>)`. **Image insert locations are chip-safe:** the chip editor's drop/paste caret is a *display*-string offset (each chip = one `U+FFFC`), so `ChipTextView.markdownIndex(forDisplayLocation:)` converts it to the *markdown* offset (`ChipMarkdownOffset`, `Domain/ChipMarkdownOffset.swift`) before inserting — otherwise a second dropped/pasted image lands inside the first ref and corrupts it. The toolbar insert-image button and the "Paste Image" menu insert at the tracked caret (`onCaretChange` → `CaretHolder`, no per-keystroke re-render), not the end. Clipboard image extraction (`NSPasteboard.imagePNGData()`) reads explicit `public.png`/`.tiff`/`.jpeg`/`.heic` data types (normalised to PNG) before falling back to `NSImage(pasteboard:)`, so pasting images that aren't plain `NSImage`s works instead of dropping to text. `ChipTextView` overrides `readablePasteboardTypes` to advertise image + file-URL + its private chip-markdown type, so an image-only clipboard (a screen capture) keeps Paste enabled (macOS otherwise disables ⌘V and beeps before the override runs). **Cut/copy/paste of chips round-trips** via that private `com.gbpdiary.note-markdown` pasteboard type (a plain RTFD copy would lose the managed attachment): copy/cut serialize the selection to markdown, paste re-inserts it through the chip-rebuilding path — a cut image is *moved* (same attachment, no duplicate file). **Typing sync (no caret-jump/scramble):** every self-originated edit (`textDidChange`/`insert`/`applyResult`) updates the coordinator's `lastMarkdown` synchronously but pushes the SwiftUI `text` binding **asynchronously** (via `pushMarkdownToSwiftUI`, deferred to avoid a mid-edit layout storm). To stop a lagging push from being mistaken for an external change and reverting the buffer, each push is recorded in `pendingEchoes` and `updateNSView` consults the pure `MarkdownEditorSync.shouldRebuild(incoming:buffer:pendingEchoes:)` — rebuild only for a genuine external change, never for a stale self-echo. A `refreshToken` bump rebuilds from the buffer's *current* serialized content (preserving un-echoed in-flight typing). **Per-image manual sizing:** `Attachment.displayWidthPercent` (a % of the note width, set with a slider in `NoteImageEditSheet`, opened by tapping a chip; nil = 100%/fit) sizes an image in the preview via a **custom Textual image loader** (`SizedImageLoader`/`SizedImageAttachment`, `Views/Notes/SizedImageAttachment.swift`) whose `sizeThatFits` uses the pure `ImageDisplaySize.fit(intrinsic:proposedWidth:widthFraction:)` (fraction-of-pane, never upscale, aspect-preserving) applied via `.noteImageSizing(note.attachments)`. The original full-resolution file is untouched, so `MinutesExport`/downloads stay full-res.
- `NoteEditorSheet` — sheet for editing `Note.project` and `Note.tags` (content is always edited inline). Accepts `note: Note`.
- `ActivitySection` — top section in `DayPageContent`. Renders focus blocks and standalone (out-of-range) entries interleaved chronologically (`activityItems`); `ActivityEntryRow` is reused for standalone entries at block-indent level. **Block membership is a pure function of each entry's time** — `entries(for:)` and `standaloneEntries` call `FocusBlockAssignment.containingBlock`; nothing is stored, synced, or normalized, so entries move automatically when their time or the blocks change (`FocusBlockRow` receives its entries rather than querying by relationship). No blocks are auto-created; there is no Unspecified group. Footer shows Total and, separately, Overtime (evening logged hours). `FocusBlockRow` context menu has Edit + Delete.
- `FocusBlockEditorSheet` — create/edit a `FocusBlock`. Evening is additive (always addable); when the slot is Evening a start-time picker (default 18:00) sets `startTime`; evening has no capacity.
- `LogTimeSheet` — logs a `TaskTimeEntry`; pre-selects the slot-matching block (12:30 split; evening if present). Blocks without a task/project show just their slot name.
- `FocusBlockRow` — collapsible row for one `FocusBlock`. Shows source icon (folder for project-backed, checkmark for task-backed), slot/duration chip, net remaining time label, "+" to open `LogTimeSheet`, pencil to edit. Context menu includes delete with alert when activities exist.
- `FocusBlockEditorSheet` — sheet for creating or editing a `FocusBlock`. **Time is only ever assigned to tasks**, so a standard block is always task-backed (a single task picker — no Task/Project source toggle); an evening block is a pure overtime container with no task. `save()` always clears the legacy `block.project`.
- `LogTimeSheet` — lightweight sheet for adding a `TaskTimeEntry`. Pre-fillable with `presetTask`, `presetFocusBlock`, `presetDate`, `presetEmail` (legacy per-message), or `presetConversation` (logs against the `EmailConversation`, which owns its time). Task picker shown when no preset task/email/conversation; a preset email/conversation shows a read-only context section instead.
- `DayTaskSidebar` — collapsible sidebar with Scheduled and Inbox sections for a given day. (Legacy; superseded by `DayTaskPanel`.)
- `DayTaskPanel` (`Views/DayTab/DayTaskPanel.swift`) — the diary's always-visible right-hand **"My Active Tasks"** panel, **scoped to tasks assigned to the "Me" person** (`AppSettingsStore.myPersonID`; falls back to all tasks when Me isn't configured). A lean **`ListToolbar`** (search + **Filters ▾** popover + active-filter row; no presets — the panel only shows open tasks and all are Me) filters through `FilterEngine`/`FuzzyMatch` over a focused `panelFilters` set (Project / Priority / Tag / From-email) before bucketing. Then a **quick-add** capture field (creates a `Task` **assigned to Me** → lands in the Inbox) plus collapsible buckets **Overdue · Due today · In-progress · Scheduled · To Do · Inbox** (partitioned by `DayTaskBuckets`; **To Do** is the catch-all so every open, triaged, top-level task is visible even when undated, ordered by `TaskUrgency.score`). Action buckets use a compact **two-line `DayTaskPanelRow`** (email-list style: status icon + metadata chips [project/priority/due/scheduled/flags] on line 1 with a trailing **time quick-add `Menu`** [15m/30m/1h/1.5h/2h/Custom… → logs a `TaskTimeEntry` at the current time-of-day on the shown diary day, so it slots into the Activity timeline chronologically], summary on line 2; **no edit button — double-click opens the editor**, status/log-time/delete in the context menu); the Inbox uses `TaskTriageRow`, whose priority is a **one-click L/M/H toggle** (tap to set, tap the active one to clear). **Reviewed is disabled until the task has a project** (UI gate — `TaskTriageRow.canReview = task.project != nil`; `markReviewed()` itself is unguarded). Placed beside the day/week content by `DiaryView` in a macOS `HSplitView` (toggle in the diary bar, persisted via `AppSettingsStore.taskPanelShown`).
- `DaySectionHeader` — reusable section header with title and optional "+" button.
- `CompletedTaskRow` — read-only struck-through task row with completion time; tap opens `TaskEditorSheet`.
- `DayDocumentRow` — document row in the day's Documents section. Shows icon + summary + attachment count chip (gray) + pencil edit button on the first line; `documentDescription` as caption on the second line when non-empty. Requires `onEdit: () -> Void`.
- `TasksView` — filterable macOS Table (or List on iOS) of all tasks. Filter controls in `TasksFilterBar`.
- `MinutesDetailView(minutes:asSheet:)` — unified meeting editor (metadata + minutes markdown). Rendered as a workspace tab (`asSheet: false`) or a sheet. **New-meeting flow (`isNew`, sheet):** confirming ("Add") sets `isConfirmed`, opens the meeting in its own tab (`openMinutesForEditing`), and dismisses; Cancel/Escape deletes the orphan record (`performDelete`). Because opening that tab switches the active tab and tears down the diary subtree hosting the sheet — which can reset the sheet's `@State` — the `onDisappear` orphan-cleanup is **guarded by `!workspace.references(minutes.persistentModelID)`**: it never deletes a meeting that's already open in a tab (a deleted-but-displayed `Minutes` crashes the tab reading `meetingAt`). Layout: summary title, a compact metadata block (Projects / Time / Duration / Attendees — Duration is preset chips plus an inline content-sized custom chip with lenient parsing), then the `MarkdownDocumentEditor` for the minutes note (auto-created via `ensureNoteExists`). In tab mode the **summary + metadata header is pinned** (only the body below scrolls), and the body leads with a **`DayActionBar`** (same component/style as the diary page) with **Add action item / Add document / Download minutes / Download PDF**. The title has the meeting **date/time as a subheading**. The `DayActionBar` is **pinned with the header** (doesn't scroll). Below the bar: an **Action Items** section (rows are compact `MeetingActionRow`s — status toggle + summary + assignee/date chips, whole-row tap opens the editor, no edit icon) (`Minutes.newTasks`; the top button opens `TaskEditorSheet` seeded with `presetProject:`/`originMinutes:`/`attendees:`/`requireAssignee: true` — the assignee defaults to the **"Me"** person from Settings (`AppSettingsStore.myPersonID`, else a "Greg Poole" name fallback); attendee chips are one-tap single-select assignee toggles styled neutral=off / green=on, and a save requires an assignee. On create it inserts a bold `**Action <INITIALS>: <summary> (due …)**` on a new line at the minutes cursor — bulleted to match the current list level via `insertOnNewLine` — through `MarkdownDocumentEditor.EditorInsertionRequest`) and a **Documents** section (`Minutes.documents`; the top "Add document" creates a linked `Document` and opens `DocumentEditorSheet(requireAttachment: true)` — which has a **Files** section (`.fileImporter` + attachment list) and blocks Save until ≥1 file; dismissing with no files discards the doc. Or link existing / create inline via the section's `FuzzyPickerField`. Rows are single-line (icon + title + "N files", no chip) and open the doc tab). **Download minutes / Download PDF** (macOS) export the composed meeting (header + Action Items + Documents + body) as `.md`/`.zip`/themed PDF — the renderer internals (`MinutesExport`, `NotePDFSegments`, `ExportPalette`, `MinutesExportView`, `NSHostingView.dataWithPDF`, and the three rejected renderers) are documented in the **`minutes-export`** skill (`.claude/skills/minutes-export/SKILL.md`). The macOS **Settings** window is a `TabView` (**General** → the "Me" default-assignee person picker; **Calendar** → `CalendarSettingsView`, checkboxes over `CalendarService.calendars()` persisting `AppSettingsStore.defaultCalendarIDs`; **Email** → `EmailSettingsView`; **Shortcuts** → `HotkeySettingsView`, the configurable app hotkeys — see the Configurable hotkeys bullet in Navigation; **Appearance** → `AppearanceSettingsView`, the **page (PDF export) palette** picker (`AppSettingsStore.pagePalette`; the on-screen theme is fixed to Kanagawa dark for now)), with the shared model container + `HotkeySettings` injected so the pickers can query and the shortcut pane can bind. The meeting-import picker pre-activates those default calendars: `MinutesDetailView.defaultCalendarFilterIds` maps the stored ids to the picker's `cal:<id>` chip ids intersected with calendars that have events, passed to `FuzzyPickerField(defaultActiveFilterIds:)` (empty = all calendars shown). The minutes `MarkdownDocumentEditor` runs with `showsFormattingToolbar: true` (see that component for the toolbar/shortcuts/list-editing/spell-check/heading-colour behaviors).
- `ImageLibraryView` (`Views/ImagesTab/`) — the Images sidebar tab. Tables all image `Attachment`s with thumbnail, display name, description, usage (referencing notes via `AttachmentUsageScanner` / "Document" / "Unused"), and size. Per-row delete enabled only for unused images; "Delete Unused" bulk action; sidebar badge shows the unused count. `ImageDetailSheet` edits display name/description and lists referencing notes as links that call `WorkspaceModel.reveal(note:)`.
- `WorkspaceView` / `WorkspaceModel` / `WorkspaceTabStrip` (`Views/Workspace/`) — the shell: browse sidebar + per-tab back/forward history. See the Navigation section.
- `DocumentDetailView(document:asSheet:)` — same pattern for `Document`.
- `ProjectDetailView(project:asSheet:)` — a page-styled detail view (`AppTheme.background` + `DaySectionHeader` sections, injecting `@Environment(WorkspaceModel.self)`; **not** the GroupBox stack). A **minutes-style header** leads: project name (`.title2.weight(.semibold)`), the **Active/Completed status control**, then a `metaRow`-based **inline-editable** metadata card (`AppTheme.cardRaised.opacity(0.3)` rounded card, mirroring `MinutesDetailView.metadataHeader`) covering the project-table fields, each bound directly to the model (no separate editor needed) — Description/Stream/Tags as `TextField`s, Parent and **Dev Team**/**Sci Team** (each with a Lead sub-picker; lead auto-set to the first member when the team is non-empty) as `FuzzyPickerField`s, plus a read-only Last Meeting row. The header + a **`DayActionBar`** (same component/style as the diary and minutes pages) are **pinned** (only the sections below scroll); the bar's actions are **Add meeting** (`MinutesEditorSheet`), **Add document** (creates a project-linked `Document` and opens `DocumentEditorSheet(requireAttachment: true)`), and **Add subproject** (opens `ProjectEditorSheet(project: nil, defaultParent: project)` — a new-project form with the parent preset; nothing is inserted until Save, and on Save the sheet's `onCreated` opens the new subproject in a new tab via `workspace.openInNewTab(.project(id))`). There is no top-right pencil — all metadata is inline-editable and project **Delete** lives on the Projects table's bulk bar. Sections follow in priority order: **Open Tasks**, **Meetings** (**double-click a row opens the meeting in a new tab** via `workspace.openInNewTab(.minutes(id))`), **Documents** (**double-click opens the document tab** `workspace.focusOrOpen(.document(id))`), **Subprojects** (double-click → `focusOrOpen(.project(id))`), **Notes** (tap → `NoteEditorSheet`), and **Completed Tasks** (a `DisclosureGroup` **collapsed by default**). The **status control** is the only place `Project.isCompleted` is set in-app and enforces the hierarchy invariant via `ProjectStatusRules` (`Domain/`): **Mark Completed** is disabled until all subprojects are Completed; **Reactivate** is disabled while the parent is Completed (reactivate the parent first). Disabled controls show a caption explaining why.
- `PersonDetailView(person:asSheet:)` — the `.person` tab, styled like `ProjectDetailView` (page style: `AppTheme.background` + a pinned title + a minutes-style **inline-editable** metadata card, then scrolling `DaySectionHeader` sections — **not** the GroupBox stack). Double-clicking a person in `PeopleView` opens this in a tab (`workspace.focusOrOpen(.person(id))`). The metadata card edits **Name / Emails (`EmailListEditor`) / Institution (`FuzzyPickerField`, create-inline) / Tags** live (each binding stamps `updatedAt`); no pencil/editor sheet. Sections: **Open Tasks** (assignee, todo/started), **Projects** (`Person.teamProjects` — deduped dev+sci team membership, each row a role chip [Dev/Sci/Dev·Sci] + Lead marker, double-click → `focusOrOpen(.project(id))`), **Meetings** (attended, double-click → `openInNewTab(.minutes(id))`), and **Completed Tasks** (collapsed `DisclosureGroup`). `PersonEditorSheet` (still the app's edit-modal style) is now used only for **creating** a person (the People page "+"), and offers **Delete** when editing an existing one; person **Delete** otherwise lives on the People table's bulk bar. The metadata sheet form of `MinutesDetailView` (`asSheet`) bounds its height and scrolls a long attendee list so the Cancel/Add bar stays visible.
- `InstitutionDetailView(institution:asSheet:)` — same pattern for `Institution`.
- `TagsView` — computed table of all unique tags used across `Project.tags` and `Person.tags`. Columns: tag name, project count, people count. Tap a row to open `TagDetailSheet` showing chips for all matching projects and people. No model of its own; derives from `@Query` on `Project` and `Person`.
- All list pages follow the canonical **List / Table page style** (see that section): `VStack { ListToolbar + BulkActionBar? + Divider + Table }`; macOS `Table` with resizable header-sortable columns, native selection, and `.onTableRowDoubleClick` to open; iOS `List` single-tap. All list pages (`TasksView`, `ProjectsView`, `PeopleView`, `MinutesListView`, `DocumentsListView`, `ContentListView`, `InstitutionsView`, `TagsView`, `ImageLibraryView`) are on the shared components. `TagsView` (derived — search + sortable columns, no bulk bar) sorts its `TagEntry` columns via keypaths. `ImageLibraryView` keeps its bespoke unused-only Delete (per-row + "Delete Unused") rather than a generic selection-delete — deleting an in-use image would break note image links — and its thumbnail / "Used in" / trash columns are not header-sortable (no comparable / cross-note scan).) **`ProjectsView` is hierarchical**: rows are flattened parent→child via `ProjectHierarchy.rows` (`Domain/ProjectHierarchy.swift`) — subprojects indented under parents (any depth), header sort orders *siblings* within the tree, and filtering keeps each match's ancestor chain visible as **dimmed context** rows (`isMatch == false`) so matches stand out.

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
- **Entity-detail-as-tab**: Institution / Document list views still open details via `.sheet(item:)`; route these through `WorkspaceModel` for in-place tab navigation. (Project and Person already open as tabs.)
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
| `TimeFormat.short(hours:)` renders minute-scale email time: "Nm" under an hour, "Nh" for whole hours, else "Hh Mm"; a tiny non-zero value rounds up to "1m"; 0 → "0m" | Email time-logging / activity | gbpDiaryTests/Domain/TimeFormatTests.swift | `short_zero_isZeroMinutes`, `short_tinyValue_roundsUpToOneMinute`, `short_minutesUnderAnHour`, `short_wholeHours`, `short_mixedHoursAndMinutes` |
| Timesheet includes only completed tasks with duration in selected interval | Timesheet | gbpDiaryTests/Domain/TimesheetComputationTests.swift | `tasksInRange_requiresCompletedAtAndDuration` |
| Scheduled filter uses `scheduledAt` in `[dayStart, dayEnd)` and todo/started status | Day view sections | gbpDiaryTests/Domain/DayTaskFilteringTests.swift | `scheduled_requiresTodoOrStartedAndWithinDayBounds`, `scheduled_excludesTasksAlreadyInEntries` |
| Inbox filter: open (todo/started), top-level (parent == nil), `needsTriage` — enriching no longer removes a task, only Review does | Task inbox / triage | gbpDiaryTests/Domain/DayTaskFilteringTests.swift | `inbox_includesUntriagedTopLevelActiveTasks`, `inbox_includesStartedButExcludesOtherStatuses` |
| Task inbox flag: a freshly `init`-ed Task has `needsTriage == true`; `markReviewed()` clears it (and is a no-op / doesn't bump `updatedAt` when already reviewed) | Task inbox / triage | `gbpDiaryTests/Models/TaskStateTransitionTests.swift` | `newTask_needsTriageByDefault`, `markReviewed_clearsNeedsTriage`, `markReviewed_noOpWhenAlreadyReviewed` |
| Diary task-panel buckets: `DayTaskBuckets.partition(allTasks:date:)` splits into mutually-exclusive `inbox` (untriaged, open, top-level) and — for triaged, open, top-level, non-waiting tasks — `overdue → dueToday → inProgress(.started) → scheduled(today) → todo` by priority (`todo` is the catch-all so undated tasks stay visible); the due/scheduled "today window" is `WeekendPolicy.forwardRange(for: date)`, so on a Monday weekend-dated due/scheduled tasks are due-today/scheduled (not overdue); waiting/completed/subtasks excluded; empty → empty | Diary task panel | `gbpDiaryTests/Domain/DayTaskBucketsTests.swift` | `emptyInput_isEmpty`, `inbox_isUntriagedTopLevelOpen`, `actionBuckets_assignByPriority`, `mutuallyExclusive_overdueWinsOverStarted`, `waitingTasks_excludedFromActionBuckets`, `completedAndSubtasks_excludedEverywhere`, `mondayWindow_absorbsWeekendDueAndScheduled` |
| notesId derives a stable focus ID by bit-complementing all 16 UUID bytes; result is its own inverse and never collides with organic UUIDs | Inline task notes / meeting minutes | gbpDiaryTests/Models/DayEntryContentTests.swift | (tested indirectly via `notesAreaFocusId` usage) |
| `entriesInRange` filters `TaskTimeEntry` objects whose `date` falls within the interval; `totalHours(entries:)` sums their `hoursNormalized` | Timesheet entry-based aggregation | gbpDiaryTests/Domain/TimesheetComputationTests.swift | `entriesInRange_filtersCorrectly`, `totalHours_entries_sumsHours` |
| `FocusBlockMath.netHours(capacity:loggedHours:)` = max(0, capacity − loggedHours); the view sums time-derived entry + meeting hours as `loggedHours` (FocusBlock stores no child-entry relationship) | Activity section | `gbpDiaryTests/Models/FocusBlockTests.swift` | `focusBlockMath_netHours_subtractsLogged`, `focusBlockMath_netHours_clampsToZero` |
| Meeting slot classification: morning = start < 12:30; afternoon = end ≥ 12:30; no-duration meeting is a point in time; spanning-boundary meeting appears in both slots | Activity section / `MeetingSlotClassifier` | `gbpDiaryTests/Domain/MeetingSlotTests.swift` | `slots_morningOnly_noDuration`, `slots_afternoonOnly_noduration`, `slots_spansNoon_morningStartLongDuration`, `slots_morningOnly_shortDurationEndsBeforeNoon`, `slots_before1230_isMorning`, `slots_exactlyAt1230_isAfternoon`, `slots_endsExactlyAt1230_spansBoundary` |
| Entry slot classification: before 12:30 → morning; ≥ 12:30 → afternoon; ≥ evening start → evening only when an evening block exists (flexible start); evening has no capacity and is overtime | Focus blocks / `DaySlotClassifier` | `gbpDiaryTests/Domain/DaySlotClassifierTests.swift` | `before1230_isMorning`, `atOrAfter1230_isAfternoon`, `withoutEveningBlock_lateTimeStaysAfternoon`, `withEveningBlock_afterStartIsEvening`, `flexibleEveningStart_isRespected`, `daySlot_evening_hasNoStandardCapacity_andIsOvertime` |
| `FocusBlockAssignment.containingBlock` attaches an entry to the block whose range contains its time (evening wins; morning/afternoon fall back to all-day), or nil (standalone) when none covers it; never creates blocks | Focus blocks / activity grouping | `gbpDiaryTests/Models/FocusBlockTests.swift` | `containingBlock_matchesSlotByTime`, `containingBlock_fallsBackToAllDay`, `containingBlock_eveningWinsAfterItsStart`, `containingBlock_nilWhenOutOfRange` |
| Time is only assigned to tasks, not projects: `FocusBlockProjectMigration.plan` splits focus blocks still carrying a legacy `project` into two buckets — project-only blocks (no task) grouped by project in `tasksPerProject`, and task-backed-with-stale-project blocks in `clearProject`; blocks with no project are left alone; idempotent by design. The one-time launch migration (`WorkspaceView.migrateFocusBlockProjectsOnce`) backs each `tasksPerProject` group with one auto-created, **already-completed** per-project task and nulls the project, and just nulls the project on each `clearProject` block (the task owns it). The editor (`FocusBlockEditorSheet`) no longer offers a Project source | Focus blocks / task-only time | `gbpDiaryTests/Domain/FocusBlockProjectMigrationTests.swift` | `plan_emptyInput_isEmpty`, `plan_projectOnlyBlock_goesToTaskCreationBucket`, `plan_taskBackedWithStaleProject_goesToClearBucket`, `plan_taskBackedNoProject_isLeftAlone`, `plan_projectlessNoTask_isLeftAlone`, `plan_groupsMultipleProjectOnlyBlocksByProject`, `plan_mixedInput_splitsAcrossBothBuckets` |
| `Task.setDuration` stores duration; auto-completes todo and started tasks (only when completedAt == nil); does NOT overwrite existing completedAt | Task state transitions | `gbpDiaryTests/Models/TaskStateTransitionTests.swift` | `setDuration_completesTodoTaskAndStoresDuration`, `setDuration_completesStartedTask`, `setDuration_doesNotOverwriteExistingCompletedAt` |
| `Task.loggedHoursNormalized` sums `hoursNormalized` across all `timeEntries`; returns 0 when empty. `Task.loggedDuration` returns nil when no entries, else a Duration in hours | Timesheet / Activity section | `gbpDiaryTests/Models/TaskComputedPropertyTests.swift` | `loggedHoursNormalized_sumsAllTimeEntries`, `loggedHoursNormalized_emptyEntries_returnsZero`, `loggedDuration_returnsNilWhenNoEntries`, `loggedDuration_returnsNonNilWithSummedHours` |
| `Task.needsChevron` is true when the task has children OR a non-empty notes string; false for empty-string notes | UI expand/collapse indicator | `gbpDiaryTests/Models/TaskComputedPropertyTests.swift` | `needsChevron_trueWhenHasChildren`, `needsChevron_trueWhenHasNonEmptyNotes`, `needsChevron_falseWhenNoChildrenOrNotes`, `needsChevron_falseWhenNotesIsEmptyString` |
| `DaySlot.defaultDuration`: allDay=1.0d (7.6h), morning=0.5d (3.8h), afternoon=0.5d (3.8h), evening=0h (overtime container) | Focus block scheduling | `gbpDiaryTests/Models/ValueTypesTests.swift`, `gbpDiaryTests/Domain/DaySlotClassifierTests.swift` | `daySlot_defaultDuration_allDay_isOneDay`, `daySlot_defaultDuration_morning_isHalfDay`, `daySlot_defaultDuration_afternoon_isHalfDay`, `daySlot_evening_hasNoStandardCapacity_andIsOvertime` |
| `notesId(for:)` is its own inverse: `notesId(notesId(x)) == x`; always produces a UUID distinct from the input | Inline notes focus management | `gbpDiaryTests/Models/DayEntryContentTests.swift` | `notesId_isOwnInverse`, `notesId_differFromSourceId` |
| `Task.clearFollowUp()` clears `followUpAt` and reverts `.followUpPending` → `.completed`; no-op on other statuses | Task state transitions | `gbpDiaryTests/Models/TaskStateTransitionTests.swift` | `clearFollowUp_revertsToCompleted`, `clearFollowUp_noOpWhenNotFollowUpPending` |
| Managed image refs: `AttachmentRef.url(for:)`/`markdown(for:)` produce `attachment://<uuid>` refs; `id(fromURL:)` parses them (rejecting other schemes/non-UUIDs); `referencedIDs(in:)` extracts all image-ref ids from markdown in order | Markdown notes / managed images | `gbpDiaryTests/Models/AttachmentRefTests.swift` | `url_and_id_roundTrip`, `id_fromURL_rejectsNonAttachmentSchemes`, `markdown_embedsDisplayNameAndRef`, `markdown_sanitizesClosingBracketInDisplayName`, `referencedIDs_extractsAllInOrder`, `referencedIDs_ignoresPlainLinksAndNonAttachmentImages` |
| Chip-editor insert offset: `ChipMarkdownOffset.markdownOffset(displayLocation:runs:)` maps a display-string caret (chips = 1 char) to the markdown offset (chips expand to their full ref), so image drop/paste lands correctly when the note already has chips; 1:1 in plain text, atomic across chips, clamped past the end | Note image insert / chip editor | `gbpDiaryTests/Domain/ChipMarkdownOffsetTests.swift` | `offset_atStart_isZero`, `offset_withinFirstPlainRun_isOneToOne`, `offset_beforeChip_countsPrecedingText`, `offset_afterChip_includesFullRefLength`, `offset_withinTrailingText_addsOffsetPastChip`, `offset_atEnd_isTotalMarkdownLength`, `offset_beyondEnd_clampsToTotal`, `offset_noChips_isIdentity`, `offset_twoAdjacentChips` |
| Chip-editor typing sync: `MarkdownEditorSync.shouldRebuild(incoming:buffer:pendingEchoes:)` returns true only for a genuine external change — when the incoming binding value matches the buffer it clears the queue and returns false; when it matches a queued self-push it consumes up to that echo and returns false (so a lagging async echo of the user's own typing never reverts the buffer / jumps the caret); otherwise clears the queue and returns true | Note editor / typing sync | `gbpDiaryTests/Domain/MarkdownEditorSyncTests.swift` | `inSync_returnsFalse_andClearsEchoes`, `staleSelfEcho_returnsFalse_andConsumesUpToIt`, `genuineExternalChange_returnsTrue_andClearsEchoes`, `abaScrambleScenario_neverRebuildsForOwnEchoes` |
| Note image display sizing: `ImageDisplaySize.fit(intrinsic:proposedWidth:widthFraction:)` takes the given fraction of the proposed width (nil = full), never upscales past intrinsic, and preserves aspect ratio (returns intrinsic when unconstrained; unchanged for a zero-size image) | Note image sizing | `gbpDiaryTests/Domain/ImageDisplaySizeTests.swift` | `fitsToProposedWidth_whenNarrower`, `neverUpscalesPastIntrinsic`, `fractionScalesProposedWidth`, `fractionStillCapsAtIntrinsic`, `unconstrained_returnsIntrinsic`, `zeroIntrinsic_returnsUnchanged` |
| Blank-note detection: `MarkdownBlank.isBlank` is true when every line is empty or only empty markdown scaffolding — blockquote markers, a bullet/ordered marker with an optional empty checkbox, or a heading marker — with no text after it (so a lone `- ` is blank, `- item` is not); drives whether `MarkdownDocumentEditor` shows the tap-to-edit placeholder | Note editor / empty placeholder | `gbpDiaryTests/Domain/MarkdownBlankTests.swift` | `trulyEmpty_isBlank`, `loneListMarkers_areBlank`, `emptyCheckboxAndQuoteAndHeading_areBlank`, `multipleEmptyScaffoldLines_areBlank`, `anyVisibleText_isNotBlank` |
| Markdown→HTML (PDF export): `MarkdownHTML.render(_:image:)` converts headings/paragraphs, bold/italic/inline-code, links (note:// → plain text), images (`<img style="width:N%">` from the resolver), un/ordered lists incl. checkboxes, blockquotes, fenced code, hr, and tables; all text HTML-escaped | Minutes PDF export | `gbpDiaryTests/Domain/MarkdownHTMLTests.swift` | `heading`, `paragraph_escapesAndFormatsInline`, `link_andNoteLink`, `image_usesResolvedSrcAndWidth`, `image_noWidth_usesFullWidth`, `unorderedList_withCheckbox`, `orderedList`, `blockquote`, `fencedCode_escaped`, `horizontalRule`, `table` |
| Note PDF segments: `NotePDFSegments.segments(from:)` splits markdown into ordered text/image runs at inline `attachment://` refs (whitespace-only text dropped; ids/order preserved) | Minutes PDF export | `gbpDiaryTests/Domain/NotePDFSegmentsTests.swift` | `noImages_isSingleTextSegment`, `emptyMarkdown_isEmpty`, `oneImage_splitsTextImageText`, `imageOnly_isSingleImageSegment`, `multipleImages_preserveOrder` |
| Export palette: each `ExportPalette` case resolves 6 heading colours + distinct page/card backgrounds (light plain has card==page; shaded differs; dark isn't light); `css(_:)` formats `#RRGGBB`; `bodyHTMLDocument` embeds the heading colour; `AppSettingsStore.pagePalette` defaults to `lightShaded` and round-trips | Minutes PDF / appearance | `gbpDiaryTests/Domain/ExportPaletteTests.swift` | `cases_haveDistinctBackgroundsAndSixHeadings`, `css_formatsSixDigitHex`, `bodyHTMLDocument_embedsHeadingColour`, `store_pagePalette_defaultsAndRoundTrips` |
| Minutes PDF render: `MinutesExportView` rendered via `NSHostingView.dataWithPDF` (with a sized image) produces a valid non-trivial `%PDF` | Minutes PDF export | `gbpDiaryTests/Views/MinutesExportRenderTests.swift` | `exportView_dataWithPDF_producesValidPdfWithImage` |
| `AttachmentUsageScanner.orphanedIDs(candidates:contents:)` returns attachment ids referenced by no note markdown; `referencedIDs(inContents:)` unions refs across contents | Image library / orphan detection | `gbpDiaryTests/Models/AttachmentRefTests.swift` | `orphanedIDs_flagsUnreferencedAttachments`, `referencedIDs_acrossContents_isUnion` |
| Obsidian import bundle preserves core relationships and task metadata when upserting into SwiftData | Obsidian import | `gbpDiaryTests/Import/ObsidianBundleImporterTests.swift` | `importBundle_createsRelationshipsAndTaskMetadata` |
| Vault-root `Notes/` files import as titled content notes (title, resolved project, no day record, `isContentNote`); inferred inline fields are stripped from note content | Obsidian import / content notes | `gbpDiaryTests/Import/ObsidianBundleImporterTests.swift`, `tools/test_obsidian_import_bundle.py` | `importBundle_createsContentNoteWithTitleAndProject`, `test_build_bundle_extracts_entities_relationships_and_tasks` |
| Obsidian import launch arguments require `--import-obsidian-bundle <path>` and support `--exit-after-import` for CLI validation runs | Obsidian import | `gbpDiaryTests/Import/ObsidianBundleImporterTests.swift` | `launchRequest_parsesBundlePathAndExitFlag`, `launchRequest_requiresBundlePath` |
| Workspace tabs are per-tab back/forward histories: `navigate(to:)` pushes (no-op on current), back/forward traverse, navigating after back truncates forward history. `openInNewTab` adds+activates; `focusOrOpen` reuses a tab showing the destination else opens one; `closeTab` reassigns active and recreates a Diary tab when the last closes | Navigation / workspace shell | `gbpDiaryTests/Views/WorkspaceModelTests.swift` | `tabState_navigate_pushesHistoryAndEnablesBack`, `tabState_navigate_toCurrentIsNoOp`, `tabState_backForward_traversesHistory`, `tabState_navigateAfterBack_truncatesForwardHistory`, `openInNewTab_addsAndActivates`, `focusOrOpen_activatesExistingTabShowingDestination`, `focusOrOpen_opensNewTabWhenNoneShowsDestination`, `closeTab_reassignsActive`, `closeTab_lastTab_recreatesDiary` |
| Safari-like tab shortcuts: `newTab()` opens+activates a Diary tab; `closeActiveTab()` closes the active tab; `selectNextTab`/`selectPreviousTab` move active with wraparound (no-op with one tab); `selectTab(at:)` activates a 0-based index (out-of-range no-op); `selectLastTab()` activates the final tab | Navigation / tab shortcuts | `gbpDiaryTests/Views/WorkspaceModelTests.swift` | `newTab_opensAndActivatesDiaryTab`, `closeActiveTab_closesCurrentAndReassigns`, `selectNextTab_wrapsAround`, `selectPreviousTab_wrapsAround`, `selectNextPrevious_singleTab_isNoOp`, `selectTabAtIndex_activatesOrIgnoresOutOfRange`, `selectLastTab_activatesFinalTab` |
| Return to previous tab (MRU back-stack): every activation funnels through `setActive(_:record:)` which pushes the left tab onto `recentTabs` (deduped, capped, never a closed tab); `returnToPreviousTab()` progressively activates the most-recent previous tab without re-pushing (`record: false`), skips/purges closed tabs, and no-ops on an empty stack; closing the active tab falls back to the most-recently-active tab (the opener) rather than the positional neighbour | Navigation / tab recency | `gbpDiaryTests/Views/WorkspaceModelTests.swift` | `returnToPreviousTab_progressivelyWalksBack`, `returnToPreviousTab_emptyStack_isNoOp`, `returnToPreviousTab_recordsPositionalAndSelectionMoves`, `returnToPreviousTab_mruDedups_noRepeatEntries`, `returnToPreviousTab_skipsAndPurgesClosedTabs`, `closeTab_returnsToTabItWasOpenedFrom_notPositionalNeighbour` |
| Configurable hotkeys: `Hotkey` round-trips Codable, renders `display` in ⌃⌥⇧⌘ order, and `isValid` requires a non-shift modifier + non-empty key; each `HotkeyAction` has a unique id, a valid default, and a section; `HotkeyResolver` returns the override else default and flags a conflicting action; `HotkeyStore`/`HotkeySettings` persist, set, and reset overrides | Configurable hotkeys | `gbpDiaryTests/Domain/HotkeysTests.swift` | `hotkey_codableRoundTrips`, `hotkey_display_ordersModifiers`, `hotkey_isValid_requiresNonShiftModifier`, `hotkey_keyEquivalentAndModifiers`, `actions_haveUniqueIdsValidDefaultsAndSections`, `resolver_overrideElseDefault`, `resolver_conflict_findsOtherActionSharingCombo`, `store_setGetClear`, `settings_setResetAndCustomisedFlag` |
| Tab drag-reorder: `TabReorder.move(order:id:toIndex:)` moves a tab id to a target index (insert-before semantics both directions), appends past the end, clamps out-of-range, and no-ops for self/unknown id; `WorkspaceModel.moveTab` applies it and preserves the active tab | Navigation / tab reorder | `gbpDiaryTests/Domain/TabReorderTests.swift`, `gbpDiaryTests/Views/WorkspaceModelTests.swift` | `move_rightward_landsBeforeTarget`, `move_leftward_landsBeforeTarget`, `move_toEnd_appends`, `move_toStart`, `move_ontoSelf_isNoOp`, `move_unknownId_returnsUnchanged`, `move_indexBeyondBounds_clampsToEnd`, `moveTab_reordersAndPreservesActive` |
| Table sort persistence: `TableSortPersistence.descriptor(for:columns:)` maps a `[KeyPathComparator]` to `(columnID, ascending)` by key path (nil for an unknown column); `order(id:ascending:columns:fallbackID:)` rebuilds the comparator, falling back when the id is unknown | Session persistence / list sort | `gbpDiaryTests/Domain/TableSortPersistenceTests.swift` | `descriptor_mapsColumnAndAscending`, `descriptor_unknownColumn_returnsNil`, `order_roundTripsDescriptor`, `order_unknownId_fallsBack` |
| Workspace session coding: `WorkspaceTabCoding` round-trips category-tab tokens (nil for unknown/entity); `entityKind(for:)` tokenises entity tabs; `WorkspaceSnapshot` JSON round-trips; `WorkspaceSessionStore` get/set/clear via UserDefaults | Session persistence / snapshot | `gbpDiaryTests/Domain/WorkspaceSessionTests.swift` | `categoryTokens_roundTrip`, `categoryToken_nilForUnknownToken`, `entityKind_tokens`, `snapshot_jsonRoundTrips`, `store_setGetClear` |
| Session restore/snapshot: `restore(_:using:)` rebuilds category tabs + active tab + diary/tasks/page filters, drops a tab whose entity UUID no longer resolves, and no-ops on a nil snapshot; `snapshot(using:)` captures entity tabs by the model's UUID and round-trips back to the entity | Session persistence / restore | `gbpDiaryTests/Views/WorkspaceModelTests.swift` | `restore_rebuildsCategoryTabsActiveAndFilters`, `restore_dropsTabWhoseEntityIsMissing`, `restore_nilSnapshot_keepsCurrentTabs`, `snapshot_capturesEntityUUID_andRestoresIt` |
| Deleted-model safety: `ModelContext.liveModel(_:as:)` returns the model for a live id (stored properties readable) but nil for a model deleted this session (in `deletedModelsArray`) or a wrong-type id — so tab-chip labels / detail routing never read a deleted SwiftData tombstone's stored properties (which traps) | Workspace / deleted-model safety | `gbpDiaryTests/Domain/LiveModelTests.swift` | `liveModel_returnsModelWhenPresent`, `liveModel_returnsNilAfterDelete`, `liveModel_wrongType_returnsNil` |
| `FilterEngine.apply` filters a collection by active `PickerFilter`s: OR within a group, AND across groups; a group with no active filter is ignored; empty active set (or only unknown ids) returns all items | List-page filtering | `gbpDiaryTests/Domain/FilterEngineTests.swift` | `apply_noActiveFilters_returnsAll`, `apply_orWithinGroup_matchesAnyInGroup`, `apply_andAcrossGroups_requiresBothGroups`, `apply_orWithinAndAndAcross_combined`, `apply_groupWithNoActiveFilter_isIgnored`, `apply_unknownActiveId_isIgnored` |
| `DateWindow.range(now:calendar:)` returns `[start, now]` for the Tasks toolbar date presets: today = start-of-today; week = 6 days before start-of-today; month = 29 days before | Tasks-page toolbar | `gbpDiaryTests/Domain/DateWindowTests.swift` | `ranges_startAndEnd` |
| `TableSelectionReconcile.reconcile(selection:stashed:visible:)` (generic over the id type) drops now-hidden selected ids into the stash and restores stashed ids that re-entered the visible set; ids that stay visible are kept; no-op when all selected are visible | List selection follows filtering | `gbpDiaryTests/Domain/TableSelectionReconcileTests.swift` | `hiddenSelection_movesToStashed`, `stashedReappearing_restoresToSelection`, `hideAndRestore_simultaneously`, `allVisible_isNoOp`, `empty_returnsEmpty` |
| Project table sort keys: `nameKey`/`streamKey` lowercase (stream defaults ""); `subprojectCount`; `lastMeetingAt` = latest meeting or `.distantPast`; `teamNames` lists lead first then others alphabetically (no dup); `teamKey` is their lowercased join | Projects table sorting | `gbpDiaryTests/Models/ProjectSortKeysTests.swift` | `streamKey_lowercasesAndDefaultsEmpty`, `nameKey_isLowercased`, `subprojectCount_countsChildren`, `lastMeetingAt_isLatestOrDistantPast`, `teamNames_leadFirstThenAlphabetical`, `teamKey_isLowercasedJoinOfTeamNames` |
| Project hierarchy: `ProjectHierarchy.rows` flattens projects parent→child (matches + transitive ancestors of matches, siblings ordered by the given comparator, depth-first with per-row depth + isMatch); filtering keeps ancestors as `isMatch==false` context and drops unrelated items; cycle/orphan safe. `ProjectsView` indents by depth and dims context rows | Projects table hierarchy | `gbpDiaryTests/Domain/ProjectHierarchyTests.swift` | `flat_allDepthZeroInSortOrder`, `threeLevelCascade_nestsDepths`, `siblings_orderedByComparator_underParent`, `filteringDeepMatch_keepsAncestorsAsContext_excludesUnrelated`, `noMatches_isEmpty`, `cycle_terminates`, `orphanParent_treatedAsRoot` |
| Project status invariant: `ProjectStatusRules.canComplete` requires every subproject Completed (leaf always ok); `canReactivate` requires the parent not Completed (nil parent ok) — a completed project never contains an active descendant | Project status | `gbpDiaryTests/Domain/ProjectStatusRulesTests.swift` | `canComplete_requiresAllSubprojectsCompleted`, `canReactivate_requiresParentNotCompleted` |
| Person table sort keys: `nameKey` lowercase; `emailKey` = primary email lowercased (or ""); `institutionKey` = institution name lowercased (or ""); `tagsKey` = lowercased comma-join of tags; `projectCount` = dev + sci project counts | People table sorting | `gbpDiaryTests/Models/PersonSortKeysTests.swift` | `nameKey_isLowercased`, `emailKey_isPrimaryLowercasedOrEmpty`, `institutionKey_isLowercasedOrEmpty`, `tagsKey_isLowercasedJoin`, `projectCount_sumsDevAndSci` |
| People search: `PersonSearch.matches(query:name:emails:institution:tags:)` fuzzy-matches (`FuzzyMatch`, case-insensitive subsequence) the query against each field individually — name, any email, institution name, or any tag — so a query never spans across fields and every email (not just primary) is searchable; empty query matches all | People page / search | `gbpDiaryTests/Domain/PersonSearchTests.swift` | `emptyQuery_matchesEverything`, `matchesName_caseInsensitive`, `matchesAnyEmail_notJustPrimary`, `matchesInstitutionAndTag`, `doesNotSpanAcrossFields`, `noMatch_returnsFalse` |
| Person team projects: `Person.teamProjects` is the union of `devProjects` + `sciProjects`, deduped by id (a person on both a project's dev and sci team appears once), sorted case-insensitively by name; drives the person page's Projects section | Person page / team projects | `gbpDiaryTests/Models/PersonTeamProjectsTests.swift` | `teamProjects_unionsDevAndSci`, `teamProjects_dedupesWhenOnBothTeams`, `teamProjects_sortedByName`, `teamProjects_emptyWhenNoTeams` |
| Minutes table sort keys: `summaryKey` = summary lowercased (or ""); `projectsKey` = sorted lowercased comma-join of project names; `attendeeCount` = attendee count (Date/Time columns sort by `meetingAt`) | Minutes table sorting | `gbpDiaryTests/Models/MinutesSortKeysTests.swift` | `summaryKey_isLowercasedOrEmpty`, `projectsKey_isSortedLowercasedJoin`, `attendeeCount_countsAttendees` |
| Document table sort keys: `summaryKey`/`descriptionKey` lowercased (or ""); `projectsKey` = sorted lowercased comma-join of project names; `attachmentCount` = attachment count (Created column sorts by `createdAt`) | Documents table sorting | `gbpDiaryTests/Models/DocumentSortKeysTests.swift` | `summaryKey_isLowercasedOrEmpty`, `descriptionKey_isLowercasedOrEmpty`, `projectsKey_isSortedLowercasedJoin`, `attachmentCount_countsAttachments` |
| Note (Content) table sort keys: `titleKey`/`projectKey` lowercased (or ""); `tagsKey` = lowercased comma-join of tags (Updated column sorts by `updatedAt`) | Content table sorting | `gbpDiaryTests/Models/ContentNoteSortKeysTests.swift` | `titleKey_isLowercased`, `tagsKey_isLowercasedJoinOrEmpty`, `projectKey_isLowercasedOrEmpty` |
| Institution table sort keys: `nameKey` lowercased; `memberCount`/`projectCount` = member/project counts | Institutions table sorting | `gbpDiaryTests/Models/ContentNoteSortKeysTests.swift` | `nameKey_isLowercased`, `memberCount_countsMembers`, `projectCount_countsProjects` |
| Attachment (Image library) sort keys: `libraryName` = display name else file name; `nameKey` = that lowercased; `descriptionKey` = description lowercased (or ""); `sizeSortKey` = byte size (or 0) | Image library table sorting | `gbpDiaryTests/Models/AttachmentSortKeysTests.swift` | `libraryName_prefersDisplayNameThenFileName`, `nameKey_isLowercasedLibraryName`, `descriptionKey_isLowercasedOrEmpty`, `sizeSortKey_isBytesOrZero` |
| Note-link refs: `NoteLinkRef.url(for:)`/`markdown(for:)` produce `note://<uuid>` links; `id(fromURL:)` parses them (rejecting other schemes/non-UUIDs); `referencedIDs(in:)` extracts all note-link ids in order, ignoring images and plain links | Content notes / linking | `gbpDiaryTests/Models/NoteLinkRefTests.swift` | `url_and_id_roundTrip`, `id_fromURL_rejectsNonNoteSchemes`, `markdown_embedsTitleAndRef`, `markdown_sanitizesClosingBracketInTitle`, `referencedIDs_extractsAllInOrder`, `referencedIDs_ignoresImageAndPlainLinks` |
| `NoteLinkUsageScanner.backlinks(to:in:)` returns ids of notes referencing the target (in order), excluding self; empty when none | Content notes / backlinks | `gbpDiaryTests/Models/NoteLinkUsageScannerTests.swift` | `backlinks_findsReferrers`, `backlinks_excludesSelfReference`, `backlinks_emptyWhenNoReferrers` |
| Content-note membership: `NoteContentMembership.isContentNote` is true iff the title is non-empty (after trimming) and the note has neither a day record nor minutes | Content notes / vault membership | `gbpDiaryTests/Models/NoteLinkUsageScannerTests.swift` | `isContentNote_requiresNonEmptyTitle`, `isContentNote_excludesDayAndMeetingNotes` |
| Calendar import mapping: title→summary (trimmed, nil if blank); start→meetingAt (not rounded); (end−start)→Duration(.h) rounded to 2dp; all-day or zero/negative length → nil duration | Calendar import | `gbpDiaryTests/Domain/CalendarEventImportTests.swift` | `minutesDraft_mapsTitleToSummary_trimmed`, `minutesDraft_blankTitle_yieldsNilSummary`, `durationHours_computesEndMinusStart`, `durationHours_zeroOrNegative_yieldsNil`, `durationHours_roundedToTwoDecimals`, `minutesDraft_timedEvent_setsDurationInHours`, `minutesDraft_allDayEvent_yieldsNilDuration`, `minutesDraft_meetingAtEqualsStart_notRounded` |
| Calendar events ordered by increasing distance of their start from a reference time (closest to now first; ties → earlier start first) | Calendar import / picker order | `gbpDiaryTests/Domain/CalendarEventImportTests.swift` | `sortedByProximity_ordersByDistanceFromReference`, `sortedByProximity_treatsPastAndFutureByAbsoluteDistance` |
| `CalendarEventImport.importWindow(around:daysBefore:daysAfter:)` returns `[start, end)` bounds from start-of-day `daysBefore` days before to start-of-day `daysAfter+1` days after `day` (normalised to start-of-day; 0/0 = a single day) | Calendar import / picker window | `gbpDiaryTests/Domain/CalendarEventImportTests.swift` | `importWindow_spansDaysBeforeAndAfter_withExclusiveEnd`, `importWindow_zeroWidth_isSingleDay`, `importWindow_normalisesToStartOfDay` |
| Markdown formatting: `MarkdownFormatting.apply(_:to:selection:)` wraps/toggles inline markers (bold/italic/code, caret-between when empty), toggles line prefixes (bullet/checkbox/quote) and renumbers ordered lists across the selected lines, sets/replaces/toggles heading level, and inserts blank-line-separated blocks (code fence, table skeleton) at the caret | Minutes note editor / formatting toolbar | `gbpDiaryTests/Domain/MarkdownFormattingTests.swift` | `bold_wrapsSelection_keepsItSelected`, `bold_emptySelection_placesCaretBetweenMarkers`, `bold_togglesOffWhenMarkersSurroundSelection`, `heading_addsMarkerToLine`, `heading_sameLevelTogglesOff`, `heading_replacesDifferentLevel`, `bulletList_prefixesEveryLineInSelection`, `bulletList_togglesOffWhenAllPrefixed`, `numberedList_renumbersSequentially`, `numberedList_togglesOff`, `checkbox_prefixesLine`, `quote_prefixesLine`, `codeBlock_insertsFencedBlockWithSeparation`, `table_insertsSkeletonAtCaret`, `table_separatesFromSurroundingText` |
| New-line insert: `MarkdownFormatting.insertOnNewLine(text:selection:insert:)` inserts on a new line after the caret's line, continuing the list/quote marker (indent + marker) when that line is a non-empty list item; uses an empty current line in place | Minutes note editor / action insert | `gbpDiaryTests/Domain/MarkdownFormattingTests.swift` | `insertOnNewLine_emptyText_insertsInPlace`, `insertOnNewLine_plainLine_startsNewLine`, `insertOnNewLine_bulletLine_continuesBullet`, `insertOnNewLine_indentedBullet_preservesIndentAndMarker` |
| List continuation: `MarkdownFormatting.returnInList(text:selection:)` on a list/quote item returns the edit to start the next item (same indent + marker; bullet char preserved, ordered incremented, checkbox reset, `>` quote continued), or removes the marker to end it on an empty item; nil on a non-list line or a non-empty selection | Minutes note editor / list continuation | `gbpDiaryTests/Domain/MarkdownFormattingTests.swift` | `returnInList_bullet_startsNewBullet`, `returnInList_preservesIndentAndBulletChar`, `returnInList_ordered_incrementsNumber`, `returnInList_checkbox_startsUncheckedItem`, `returnInList_emptyBullet_endsList`, `returnInList_emptyIndentedBullet_removesIndentAndMarker`, `returnInList_midItem_splitsOntoNewMarker`, `returnInList_quote_continuesQuote`, `returnInList_emptyQuote_endsQuote`, `returnInList_nonListLine_returnsNil`, `returnInList_withSelection_returnsNil` |
| Minutes export: `MinutesExport.rewriteImageLinks(_:relativePath:)` replaces each `attachment://<uuid>` image ref with a supplied relative path (unmapped refs untouched); `bundleFileName(id:originalFileName:)` = `<uuid>.<ext>`; `exportBaseName(summary:)` sanitises to a safe file base with a fallback; `initials(_:)` = first letter of each word uppercased; `composeMarkdown(...)` builds title + date/meta header + Action Items (`_None._` when empty) + optional Documents + `---` + body | Minutes export | `gbpDiaryTests/Domain/MinutesExportTests.swift` | `rewriteImageLinks_replacesRefsWithRelativePaths`, `rewriteImageLinks_leavesUnmappedRefsUntouched`, `bundleFileName_usesUUIDWithExtension`, `exportBaseName_sanitisesAndFallsBack`, `initials_takesFirstLetterOfEachWord`, `composeMarkdown_buildsHeaderActionsDocumentsBody`, `composeMarkdown_noneActions_andOmitsEmptyDocuments` |
| Indent/outdent: `MarkdownFormatting.indentLines(text:selection:outdent:)` quantises the primary line's leading spaces to the next/previous multiple of `indentWidth` (4) and applies that delta to every line in the selection **and any following deeper-indented child block** (any line, regardless of caret position); Shift-Tab at column 0 returns nil. `backspaceInList(text:selection:)` at the marker boundary outdents one level when indented else clears the marker; nil otherwise | Minutes note editor / list indent | `gbpDiaryTests/Domain/MarkdownFormattingTests.swift` | `indentLines_caret_addsFourSpacesAndShiftsCaret`, `indentLines_worksRegardlessOfCursorPosition`, `indentLines_quantisesPartialIndentUpToNextMultiple`, `indentLines_outdentToPreviousMultiple`, `indentLines_outdentPartialToPreviousMultiple`, `indentLines_appliesToAnyLine_notJustLists`, `indentLines_outdentAtColumnZero_returnsNil`, `indentLines_shiftsNestedChildBlockWithParent`, `indentLines_multiLineSelection_indentsBlockUniformly`, `backspaceInList_atMarkerNoIndent_clearsMarker`, `backspaceInList_atMarkerIndented_outdentsOneLevel`, `backspaceInList_notAtMarkerBoundary_returnsNil`, `backspaceInList_nonListLine_returnsNil`, `backspaceInList_checkboxMarker_clears` |
| Display name from email: drop domain; split local part on `. _ - +`; capitalise each word (first upper, rest lower); "" for empty local part | Calendar import / attendee naming | `gbpDiaryTests/Domain/CalendarEventImportTests.swift` | `displayName_fromDottedLocalPart_capitalisesWords`, `displayName_lowercasesRestAndCapitalisesFirst`, `displayName_singleWord`, `displayName_handlesUnderscoreHyphenPlus`, `displayName_noDomain` |
| Attendee resolution: match by any email in a Person's ordered list (case-insensitive) first, then exact name; else create-intent; empty→[]; blank+no-email skipped; duplicates collapse; `excludingEmails` filtered first | Calendar import | `gbpDiaryTests/Domain/AttendeeMatcherTests.swift` | `resolve_matchesByEmailCaseInsensitive`, `resolve_matchesWhenEmailIsSecondaryInList`, `resolve_matchesByExactNameWhenNoEmail`, `resolve_emailTakesPrecedenceOverName`, `resolve_noMatch_createsWithNameAndEmail`, `resolve_noMatchNoName_createsWithEmailAsName`, `resolve_emptyAttendees_returnsEmpty`, `resolve_blankNameNoEmail_isSkipped`, `resolve_duplicateAttendees_collapse`, `resolve_excludingEmails_filtersOrganizer` |
| Person emails: `emails` round-trips via JSON (default `[]`); `primaryEmail` = first (nil when empty); `appendingEmail` dedups case-insensitively preserving order and ignores blanks | Person emails | `gbpDiaryTests/Models/PersonEmailsTests.swift` | `emails_roundTripThroughJSON`, `primaryEmail_isFirstOrNil`, `appendingEmail_dedupsCaseInsensitively_preservesOrder`, `appendingEmail_ignoresBlank` |
| Legacy email migration: `migratedEmails` promotes a non-blank legacy `email` to `[email]` only when the list is empty; nil otherwise (already migrated / blank / nil) | Person emails / migration | `gbpDiaryTests/Models/PersonEmailsTests.swift` | `migratedEmails_promotesLegacyEmail_whenListEmpty`, `migratedEmails_returnsNil_whenAlreadyHasEmails`, `migratedEmails_returnsNil_whenLegacyBlank` |
| Deleting a Person removes it and nullifies references (Minutes.attendees, Task.assignee); the referencing entities survive | Relationship integrity | `gbpDiaryTests/Models/RelationshipIntegrityTests.swift` | `personDelete_nullifiesReferences` |
| Deleting an Institution nullifies its members' `institution`; deleting a Project nullifies references (Task.project, Minutes.projects); referencing entities survive | Relationship integrity / entity delete | `gbpDiaryTests/Models/RelationshipIntegrityTests.swift` | `institutionDelete_nullifiesMemberInstitution`, `projectDelete_nullifiesReferences` |
| Mail AppleScript: `script(forDay:)` embeds the day bounds + both mailboxes; `parseOutput` round-trips delimited records and rebuilds dates from components; `parseNameAddress` splits name/angle-address/bare; dedupe key (message-id based); `openMessageScript(account:mailbox:id:)` embeds the escaped account + mailbox and the unquoted integer id, and opens + activates Mail | Email summary / Mail.app | `gbpDiaryTests/Domain/MailScriptParsingTests.swift` | `script_containsDayBoundsAndBothMailboxes`, `parseOutput_*`, `parseNameAddress_*`, `dedupeKey_*`, `openMessageScript_embedsAccountMailboxIdAndOpens` |
| Email→Person matching: `EmailPersonMatching.personID(forAddress:in:)` returns the id of the Person whose ordered `emails` contain the address (case-insensitive, whitespace-trimmed); nil for no match or blank address | Email management / auto-resolve person | `gbpDiaryTests/Domain/EmailPersonMatchingTests.swift` | `personID_matchesPrimaryAddress`, `personID_matchesSecondaryAddress`, `personID_isCaseInsensitive`, `personID_nilWhenNoMatch`, `personID_nilForBlankAddress`, `personID_trimsWhitespaceBeforeMatching` |
| Email ingest classification: `EmailIngestPlanning.candidates(drafts:account:existing:)` marks each fetched draft `.ingested` / `.notChosen` / `.new` by its dedupe key against the existing-email map (key→dismissed); `defaultSelected` is on for new + ingested, off for previously-skipped; `mailbox(for:)` maps direction→INBOX/Sent | Email ingest window | `gbpDiaryTests/Domain/EmailIngestPlanningTests.swift` | `candidates_classifiesNewIngestedAndSkipped`, `defaultSelected_onForNewAndIngested_offForSkipped`, `mailbox_mapsDirection` |
| Mailing-list loopback exclusion: `EmailSelfMatching.normalizedAddresses` trims/lowercases/dedups/drops blanks; `isInboxFromSelf(direction:fromAddress:myAddresses:)` is true only for a received email whose sender is one of my own addresses (case/space-insensitive), false for sent mail, a blank address, or an empty address set | Email ingest / self-loopback | `gbpDiaryTests/Domain/EmailSelfMatchingTests.swift` | `normalizedAddresses_trimsLowercasesDedupsAndDropsBlanks`, `isInboxFromSelf_trueForInboxSenderMatch_caseAndSpaceInsensitive`, `isInboxFromSelf_falseForSentEvenWhenSenderIsMine`, `isInboxFromSelf_falseWhenSenderNotMine`, `isInboxFromSelf_falseForBlankAddressOrEmptySet` |
| Email threading: `EmailThreading.strippedSubject` removes repeated Re:/Fwd:/Fw: prefixes + trims **preserving case** (for display — `EmailThread.displaySubject`); `normalizedSubject` = that lowercased (for keying); `threadKey(subject:party:)` keys by the normalized **subject** only (standard subject threading — no RFC References headers), so a multi-party exchange on one subject stays a single thread; empty/no-subject mail falls back to the party so unrelated blanks don't merge | Diary email threading | `gbpDiaryTests/Domain/EmailThreadingTests.swift`, `gbpDiaryTests/Domain/EmailThreadBuilderTests.swift` | `normalizedSubject_stripsReplyAndForwardPrefixes`, `strippedSubject_stripsPrefixesButPreservesCase`, `threadKey_sameSubjectAcrossReplies_matches`, `threadKey_sameSubjectDifferentParty_matches`, `threadKey_differentSubject_differs`, `threadKey_emptySubject_fallsBackToParty`, `multiPartyExchangeStaysOneThread`, `sameSubjectMerges_differentSubjectSplits` |
| Email spam rules: `EmailExcludeMatching.isExcluded(fromAddress:subject:rules:)` dismisses mail matching any `EmailExcludeRule` — a **sender** rule (full address or domain `x.com`/`@x.com`) or a **subject** rule (subject *contains* the text, case-insensitive, so `[lsc-all]` catches `Re: [lsc-all] …`); `normalizePattern` lowercases sender / preserves subject case; `suggestions(forAddress:)` offers the address + `@domain`; `EmailExcludeStore` add dedups by id + remove + migrates the legacy sender string list | Email triage / spam rules | `gbpDiaryTests/Domain/EmailExcludeTests.swift` | `isExcluded_senderFullAddress_caseInsensitive`, `isExcluded_senderDomainRule_matchesAnyAddressOnDomain`, `isExcluded_subjectRule_matchesSubstringCaseInsensitively`, `isExcluded_blankOrEmpty_false`, `normalizePattern_sender_lowercases_subject_preservesCase`, `suggestions_forAddress_offersAddressAndDomain`, `store_addRemove_typedRules`, `store_migratesLegacySenderList` |
| Email project suggestions: `EmailProjectSuggestions.rank` orders AI pick first, then prior sender/thread projects by frequency, then the sender's Person projects; excludes already-assigned; dedups by id; caps | Email triage / suggestions | `gbpDiaryTests/Domain/EmailProjectSuggestionsTests.swift` | `rank_aiFirstThenPriorThenSender`, `rank_priorFrequencyAccumulates`, `rank_excludesAlreadyAssigned`, `rank_capsAndIgnoresUnknownIDs` |
| Mail range fetch: `MailScriptParsing.script(rangeStart:rangeEnd:)` embeds both datetime bounds (`mkDateTime`) for the auto-ingest window | Email auto-ingest | `gbpDiaryTests/Domain/MailScriptParsingTests.swift` | `scriptRange_embedsBothDayBounds`, `script_containsDayBoundsAccountAndMailboxes` |
| Email triage state: `EmailTriageState.from(dismissed:accepted:)` — dismissed wins, else accepted→accepted / neither→unclassified | Email triage | `gbpDiaryTests/Domain/EmailTriageTests.swift` | `state_dismissedWins`, `state_acceptedThenUnclassified` |
| Triage bucket: `EmailTriageCategory.classify(state:hasTasks:)` — dismissed wins; else a linked to-do → Tasks; else accepted → Accepted; else To triage | Email triage / task bucket | `gbpDiaryTests/Domain/EmailTriageTests.swift` | `category_classify_bucketsByStateAndTasks` |
| Thread triage bucket: `EmailTriageCategory.classifyThread(_:)` buckets a whole thread from its messages' (state, hasTasks) — any unclassified message keeps it in To triage; else any linked to-do → Tasks; else any accepted → Accepted; else Dismissed; empty → To triage. (The Emails page now shows one row per `EmailConversation` entity, bucketed by `classify(state:hasTasks:)` over the conversation's own state, and every triage action — accept/dismiss, project, importance, person, time — is a single write on the conversation) | Email triage / thread rows | `gbpDiaryTests/Domain/EmailTriageTests.swift` | `classifyThread_bucketsAWholeThread` |
| `Task.isOpen` is false only when completed/cancelled; `EmailMessage.hasTasks`/`hasOpenTask` reflect linked task presence/openness | Email→task visibility | `gbpDiaryTests/Models/TaskComputedPropertyTests.swift` | `isOpen_trueUntilCompletedOrCancelled`, `email_hasOpenTask_reflectsLinkedTaskStatuses` |
| `EmailMessage.isSummarizing` is true only while `summaryState` is `pending` (drives the sent-email activity row's summary-vs-subject display) | Activity section / sent-email summaries | `gbpDiaryTests/Models/TaskComputedPropertyTests.swift` | `email_isSummarizing_trueOnlyWhilePending` |
| Incremental fetch: `EmailIngest.fetchBounds(lastFetchedAt:now:)` — first run = full 3-day window; otherwise from `last − 10-min overlap` (clamped to the window start) to end-of-today | Email auto-ingest | `gbpDiaryTests/Domain/EmailTriageTests.swift` | `fetchBounds_firstRun_usesFullWindow`, `fetchBounds_incremental_startsJustBeforeLastFetch`, `fetchBounds_longGap_clampsToWindowStart` |
| Deleting an email nullifies its todos' `Task.originEmail` (the tasks survive, unlinked) | Email triage / make-todo | `gbpDiaryTests/Models/RelationshipIntegrityTests.swift` | `emailDelete_nullifiesTaskOriginEmail_taskSurvives` |
| AI email summaries: `EmailSummaryPrompt.build(context:…)` embeds subject (placeholder when blank) + clamped body + identity/direction/roster (omitting missing pieces); sent/received direction explicitly assigns newest-message first/second-person pronouns so the reader is always "you"; instructions prioritize the newest message over quoted history and preserve figurative meaning rather than inventing literal events; `EmailSummaryRoster.build` caps + orders priority-first, dedups by id; `EmailSummaryText.clean` trims/collapses/caps; `EmailSummaryState` raw round-trips; `EmailSummaryPlanning.needsSummary` is true for a non-dismissed pending email OR a done email with a stale prompt version | On-device email summaries | `gbpDiaryTests/Domain/EmailSummaryTests.swift` | `prompt_includesSubjectAndBody`, `prompt_blankSubject_usesPlaceholder`, `prompt_includesIdentityDirectionAndRoster`, `prompt_omitsMissingPieces`, `instructions_containKeyRules`, `instructions_prioritizeNewestMessageAndPreserveFigurativeMeaning`, `promptVersion_reflectsPerspectiveAndIdiomRules`, `roster_capsAndOrdersPriorityFirst`, `roster_dedupsById`, `clampBody_capsLengthAndTrims`, `clean_trimsCollapsesAndCaps`, `state_rawRoundTrips`, `needsSummary_pendingDismissedAndStaleVersion` |
| Mail body fetch: `MailScriptParsing.messageContentScript(account:mailbox:id:)` embeds the escaped account + mailbox and the unquoted integer id and returns `content of` the message | On-device email summaries / body fetch | `gbpDiaryTests/Domain/MailScriptParsingTests.swift` | `messageContentScript_embedsAccountMailboxIdAndReturnsContent` |
| Deleting a Person nullifies `EmailMessage.person`; deleting a Project removes it from `EmailMessage.projects`; the referenced email survives in both cases | Email management / relationship integrity | `gbpDiaryTests/Models/RelationshipIntegrityTests.swift` | `personDelete_nullifiesEmailPerson`, `projectDelete_removesEmailProjectLink` |
| Diary day rollover: `DiaryDayRollover.rolledForwardDate` returns the weekday `now` belongs to (`WeekendPolicy.weekday(for:)`, so a tracked Friday rolls to Monday over the weekend) only when `tracksToday` and the shown day is behind it; nil when not tracking, same day, or a future day (deliberate navigation preserved) | Diary navigation / day rollover | `gbpDiaryTests/Domain/DiaryDayRolloverTests.swift` | `tracksToday_pastDay_rollsForwardToToday`, `tracksToday_sameDay_staysPut`, `notTracking_pastDay_staysPut`, `tracksToday_futureDay_staysPut`, `tracksToday_fridayRollsForwardToMondayOverWeekend` |
| Weekend folding: `WeekendPolicy.isWeekend`; `weekday(for:)` resolves a weekend forward to the next Monday (weekday→itself); `steppedWeekday` skips Sat/Sun (Fri+1→Mon, Mon−1→Fri); `weekdays(ofWeekContaining:)` = Mon–Fri; `forwardRange(for:)` (Monday absorbs the preceding weekend, `Sat..<Tue`); `workRange(for:)` (Friday absorbs the following weekend, `Fri..<Mon`); plain weekdays are a single day; `logNowDate(viewedDate:now:)` stamps now's quarter-hour on the viewed day, or the real weekend time when parked on the weekday the weekend folds into | Diary / weekend handling | `gbpDiaryTests/Domain/WeekendPolicyTests.swift` | `isWeekend_saturdaySunday`, `weekday_resolvesWeekendForwardToMonday`, `steppedWeekday_skipsWeekends`, `weekdays_ofWeek_areMonToFri`, `forwardRange_mondayAbsorbsPrecedingWeekend`, `forwardRange_plainWeekdayIsSingleDay`, `workRange_fridayAbsorbsFollowingWeekend`, `workRange_plainWeekdayIsSingleDay`, `logNowDate_weekendOnGreenMonday_usesRealWeekendTime`, `logNowDate_weekday_appliesNowTimeToViewedDay`, `logNowDate_weekendButViewingAnotherDay_usesViewedDay` |
| Task priority/due flags: `TaskPriority` weights (H>M>L>none) + `short` H/M/L; `TaskFlags.isOverdue(dueAt:isOpen:)` true only for an open task due before start-of-today; `TaskFlags.isDueToday(dueAt:)` true when due falls on today | Tasks / due+priority | `gbpDiaryTests/Domain/TaskFlagsTests.swift` | `isOverdue_pastDueAndOpen`, `isDueToday_sameCalendarDay`, `priority_weightsAndShort` |
| Task urgency: `TaskUrgency.score(UrgencyInputs)` sums coefficient-weighted factors (due ramp, priority, active, scheduled, age, tags, project, blocked−, blocking+, waiting−) but returns **0 when not open** (completed/cancelled aren't ranked); `dueUrgency` ramps 0.2→1.0 (1.0 once ≥7d overdue, 0.2 once >14d out); `effectiveDue` uses a pending follow-up's date (earliest of due/follow-up) so follow-ups surface as they come due; the Tasks table default-sorts by score | Tasks / urgency auto-sort | `gbpDiaryTests/Domain/TaskUrgencyTests.swift` | `dueUrgency_rampsAndClamps`, `priority_increasesUrgency`, `blocked_penalises_blocking_boosts`, `activeAndScheduled_addUrgency`, `waiting_penalises`, `notOpen_scoresZero`, `effectiveDue_usesPendingFollowUpAndEarliest`, `ordering_overdueHighPriorityFloatsAbovePlain` |
| Fuzzy search: `FuzzyMatch.matches(query:in:)` is true iff the query characters appear in order (case-insensitive) in the text; empty query matches all | Tasks / fuzzy find | `gbpDiaryTests/Domain/FuzzyMatchTests.swift` | `matches_inOrderSubsequence`, `matches_caseInsensitiveAndEmpty` |
| Recurrence + defer: `RecurrenceRule.parse` reads `Nd/Nw/Nmo/Ny` (bare unit → 1, rejects invalid/zero); `next(after:)` advances by unit×count; `TaskFlags.isWaiting(waitUntil:)` true while the date is future; completing a recurring task spawns the next instance and an open task past `until` is auto-cancelled (`TaskRecurrenceDriver`); waiting tasks hidden on the Tasks page unless the Waiting flag is active | Tasks / recurrence + wait/until | `gbpDiaryTests/Domain/RecurrenceTests.swift` | `parse_variants`, `next_advancesByUnit`, `isWaiting_futureOnly` |
| Task dependencies: `TaskDependency.wouldCreateCycle(taskID:newBlockerID:dependsOn:)` guards "Blocked by" edits — true for a self-edge or when the new blocker already (transitively) depends on the task; `Task.isBlocked` = any prerequisite still open (auto-unblocks when blockers complete); urgency penalises blocked / boosts blocking | Tasks / dependencies | `gbpDiaryTests/Domain/TaskDependencyTests.swift` | `wouldCreateCycle_selfAndDirect`, `wouldCreateCycle_transitive`, `wouldCreateCycle_falseForAcyclic` |
| `FuzzyPickerSelection.toggling` adds an item (matched by `id`) when absent and removes it when present; single-select (`maxSelections == 1`) replaces the whole selection, multi-select appends only while under the cap (else unchanged). Shared by item taps and create-on-the-fly (`onCreateItem`) so creating a new item honors single- vs multi-select | Picker selection semantics | `gbpDiaryTests/Views/FuzzyPickerSelectionTests.swift` | `toggling_multiSelect_addsWhenAbsent`, `toggling_multiSelect_removesWhenPresent`, `toggling_multiSelect_atCap_leavesUnchanged`, `toggling_singleSelect_replacesExistingSelection`, `toggling_singleSelect_fromEmpty_selectsItem`, `toggling_singleSelect_removesWhenSameItemPresent` |
| Chat corpus projection covers projects/tasks/people/institutions/meetings/notes/days/documents, excludes dismissed email and all email bodies, includes stored email summaries, and extracts bounded PDF + supported UTF-8 attachment text with deterministic failures/caps; `(kind, UUID)` keeps cross-model identities distinct; unowned attachments link to their local file | On-device workspace Chat / corpus | `gbpDiaryTests/Domain/ChatCorpusBuilderTests.swift` | `build_projectsAllSupportedModelsAndExcludesDismissedEmail`, `attachmentExtractor_supportsUTF8TypesAndHasDeterministicFailuresAndCap`, `attachmentExtractor_extractsBoundedPDFText`, `corpusCapsAreStableRegardlessOfInputOrder`, `crossModelUUIDCollision_preservesBothDocuments`, `unownedAttachment_navigatesToItsLocalFile` |
| Chat retrieval normalizes markdown while preserving visible text/paragraphs; chunks deterministically with overlap; hybrid ranking combines lexical + semantic cosine similarity and falls back to lexical; the versioned sidecar reuses unchanged vectors, updates changed sources, deletes stale ones, distinguishes cross-model UUID collisions, and rebuilds incomplete/configuration-stale entries | On-device workspace Chat / retrieval | `gbpDiaryTests/Domain/ChatRetrievalTests.swift`, `gbpDiaryTests/Domain/ChatSemanticIndexTests.swift` | `markdownNormalizer_removesSyntaxButKeepsMeaningfulLabels`, `chunker_isDeterministicBoundedAndOverlapping`, `sourceKeyAndChunkID_includeKindForCrossModelUUIDCollision`, `cosineSimilarity_handlesOrthogonalEqualAndInvalidVectors`, `hybridRanker_usesSemanticsAndFallsBackToLexical`, `rebuildReusesUnchangedUpdatesChangedAndDeletesStale`, `crossModelUUIDCollision_indexesBothSources`, `reuseRebuildsPreviouslyEmptyBudgetSourceWhenBudgetIncreases`, `reuseIncludesChunkBudgetConfiguration`, `reuseRebuildsNilVectorsWhenSameProviderBecomesAvailable`, `searchUsesStoredVectorsAndFallsBackToLexical`, `corruptOrWrongVersionIndexIsIgnored` |
| Chat prompts bound recent history/source context and label every source; standalone capability/help questions get an immediate deterministic privacy-aware response before retrieval; contextual transformations retrieve using the preceding question, may omit awkward inline citations while retaining the prior grounded source links, and still reject unknown labels; plain-text model answers are trimmed, map valid citation labels to sources, and are rejected with actionable errors when empty or citations are unknown/missing | On-device workspace Chat / grounded answers | `gbpDiaryTests/Domain/ChatAnswerDomainTests.swift` | `boundedHistory_keepsRecentMessagesWithinCharacterLimit`, `promptBuilder_labelsSourcesAndBoundsContext`, `capabilityResponse_handlesOnlyStandaloneHelpQuestions`, `followUpTransformation_usesPriorQuestionAndAllowsCitationFreeOutput`, `followUpTransformation_requiresContextAndRejectsUnknownCitations`, `citationValidator_acceptsKnownDedupesAndRejectsUnknown`, `answerAssembly_acceptsPlainTextAndMapsCitations`, `answerAssembly_rejectsEmptyMissingAndUnknownCitations`, `answerErrors_haveActionableDescriptions` |
| Every workspace tab owns independent session-only Chat mode/messages/lab state; `openEmailExplorerInNewTab` always opens a fresh configured Chat tab; navigating away/back preserves that tab's state; changing email clears transient body/candidates but preserves the experiment prompt; request revisions reject stale A→B→A completions, each answer request is consumed once even if SwiftUI restarts its task, and Clear invalidates in-flight answers; restoring `.chat` resets to Database/no selected email; token is `chat` | Chat navigation / Email Summary Lab | `gbpDiaryTests/Views/WorkspaceModelTests.swift`, `gbpDiaryTests/Domain/WorkspaceSessionTests.swift` | `openEmailExplorerInNewTab_alwaysCreatesConfiguredIndependentChatTab`, `chatState_survivesNavigationWithinItsWorkspaceTab`, `chatState_changingEmailClearsTransientLabDataButKeepsPrompt`, `chatState_selectionRevision_rejectsOldAAfterAtoBtoA`, `chatState_staleLabFinish_doesNotClearNewerSpinner`, `chatState_clearChat_invalidatesInFlightAnswer`, `chatState_answerRequest_isConsumedOnlyOnce`, `restore_chatStartsWithDefaultSessionOnlyState`, `categoryTokens_roundTrip` |
| Adopting an Email Summary Lab candidate trims/cleans non-empty output, stores `.done`, and records the selected prompt version; blank candidates cannot be adopted | Email Summary Lab / candidate adoption | `gbpDiaryTests/Domain/EmailSummaryExperimentTests.swift` | `adoption_trimsAndMarksSummaryDoneAtCurrentVersion`, `adoption_rejectsBlankSummary` |
| Chat query scope: `ChatQueryScopeParser.parse` detects requested kinds (singular/plural, dropping `.project` when a project is named), the longest matching known project name (punctuation-tolerant), a date interval + label (named periods / "past N units" / "recent"), and the `wantsOverview`/`wantsTimeTotals` flags (totals also from "totals"/"time totals"); empty scope when no signals. A back-referencing follow-up (`isBackReference` — "that"/"as well"/"same"/"again", excluding "this/these") inherits the prior question's project/interval/kind via `scope.inheriting(from:)` (only filling unspecified fields) | Chat / query-scoped retrieval | `gbpDiaryTests/Domain/ChatQueryScopeTests.swift` | `emailsForProject_detectsKind_projectAndDropsProjectKind`, `projectMatch_prefersLongestKnownName`, `kinds_detectSingularAndPlural`, `interval_namedPeriods`, `interval_pastN`, `overviewAndTimeTotals_flags`, `empty_whenNoSignals`, `wantsTimeTotals_detectsTotalsPhrasings`, `isBackReference_detectsFollowUps`, `inheriting_fillsUnspecifiedFieldsFromPriorScope`, `inheriting_doesNotOverrideSpecifiedFields` |
| Chat scoped ranking: `ChatScopedRanking.apply` soft-restricts hybrid-ranked chunks to the scope's kind(s)+project (falling back to the unscoped ranking when that empties, since metadata may be missing), then applies any interval as a **hard** bound — dropping out-of-window chunks with no fallback and ordering the rest newest-first — so an explicit "last week" never surfaces an out-of-window item; returns the input unchanged for an empty scope | Chat / scoped retrieval | `gbpDiaryTests/Domain/ChatScopedRankingTests.swift` | `noScope_returnsUnchanged`, `filtersByKindAndProject`, `intervalOrdersRecentFirstAndDropsOutOfWindow`, `emptyFilter_fallsBackToUnscoped`, `intervalWithNothingInWindow_returnsEmptyNotOutOfWindow`, `intervalDropsOutOfWindow_evenWhenProjectFallbackApplies` |
| Chat time totals: `ChatTimeTotals.compute(records:interval:projectName:)` sums only in-interval records (optionally project-filtered), dedupes by source key, and reports per-project (desc) + overall hours; `authoritativeBlock` renders the report-these-exact-figures prompt block (nil when empty) | Chat / deterministic time totals | `gbpDiaryTests/Domain/ChatTimeTotalsTests.swift` | `sumsOnlyInIntervalRecords`, `dedupesBySourceKey`, `perProjectDescendingAndProjectFilter`, `empty_whenNoInIntervalRecords`, `authoritativeBlock_formatsFigures` |
| Chat synthesis prompt: `ChatPromptBuilder.build` (non-transformation) instructs a grouped, condensed summary (themed bullets by default, prose when `wantsOverview`), grouping by project across projects, reports a supplied `computedTotals` block verbatim, and nudges the model to **lead with higher-importance sources**; still labels sources `[S1]…`. A `requiresCitation:` override lets the database synthesis path accept an un-cited summary (falling back to the ranked sources) while still rejecting hallucinated labels | Chat / grounded answers | `gbpDiaryTests/Domain/ChatAnswerDomainTests.swift` | `promptBuilder_synthesisInstructionAndOverviewToggleAndTotals`, `synthesisAnswer_allowsUncitedSummaryAndUsesRankedSourcesAsFallback` |
| Email importance: `EmailImportance` (H/M/L) `short`/`weight`/`rank`; `.low` default is neutral (weight 0). `EmailMessage.importance` round-trips through `importanceRaw` (unknown → `.low`); `isImportant` false only for `.low` | Email importance | `gbpDiaryTests/Models/EmailImportanceTests.swift` | `enum_shortWeightRankAndOrdering`, `message_defaultsToLow_andIsNotImportant`, `message_importance_roundTripsThroughRaw`, `message_unknownRaw_fallsBackToLow` |
| Chat importance boost: `ChatImportanceBoost.adjust(score:importanceWeight:)` leaves Low (weight 0) unchanged, scales Medium/High monotonically (High = +25%), keeps a zero-relevance chunk at 0, and stays mild enough not to overtake a much-higher base score; `ChatCorpusBuilder` sets `importanceWeight` on the email document (+ an `Importance:` field for M/H only) and `projectionVersion == 3`; `ChatScopedRanking` breaks an exact date tie by importance | Chat / email importance | `gbpDiaryTests/Domain/ChatImportanceBoostTests.swift`, `gbpDiaryTests/Domain/ChatCorpusBuilderTests.swift`, `gbpDiaryTests/Domain/ChatScopedRankingTests.swift` | `lowWeight_leavesScoreUnchanged`, `mediumAndHigh_scaleMonotonically`, `zeroScore_staysZero`, `mildBoost_doesNotOvertakeAMuchHigherBaseScore`, `email_carriesImportanceWeightAndFieldForMediumHighOnly`, `projectionVersion_isCurrent`, `interval_sameDate_importanceBreaksTie` |
| Chat answer pipeline: `ChatAnswerPipeline.run` reproduces the full orchestration (capability → follow-up/scope+inherit → retrieve → scope-filter → deterministic totals → prompt → model → assembly) over injected `retrieve`/`ChatAnswering`, exposing scope/sources/`computedTotals`/prompt and a capability·noResults·unavailable·answered·generationFailed outcome | Chat / answer orchestration | `gbpDiaryTests/Domain/ChatEvalTests.swift` | `capability_shortCircuitsBeforeRetrieval`, `noResults_whenIntervalWindowIsEmpty`, `unavailableModel_returnsSourcesNotAnswer`, `generationFailure_degradesToSources`, `answered_mapsCitationsFromPromptSources` |
| Chat evaluation harness: representative questions run end-to-end through `ChatAnswerPipeline` over the fixed `ChatEvalCorpus` with a mock answerer assert deterministic scope, must-include/must-exclude sources (a "last week" question never surfaces a February meeting), exact interval time totals, follow-up scope inheritance, prompt shape (grouped bullets; no totals instruction unless requested), and that the pipeline takes its scope from the injected `ChatScopeResolving` | Chat / eval harness | `gbpDiaryTests/Domain/ChatEvalTests.swift` | `scope_emailsForProjectInInterval`, `retrieval_lastWeekEmails_scopeToProjectAndWindow`, `retrieval_lastWeek_neverSurfacesFebruaryMeeting`, `totals_computedDeterministicallyOverInterval`, `totals_notRequested_promptForbidsInventingThem`, `followUp_inheritsPriorProjectIntervalAndKind`, `prompt_defaultsToGroupedBullets`, `pipeline_usesInjectedScopeResolver` |
| Weekend fold in Chat: `WeekendPolicy.workWeekday` folds a weekend date back to the preceding Friday (weekday → itself); `ChatWeekendFold.fold(kind:)` picks the direction by source kind (meeting → Friday, email/task → Monday) and `foldWork` always → Friday; the corpus emits weekend-folded weekday dates + sort dates and `ChatView.timeRecords` folds logged time, so the model never sees a Saturday | Chat / weekend fidelity | `gbpDiaryTests/Domain/WeekendPolicyTests.swift`, `gbpDiaryTests/Domain/ChatWeekendFoldTests.swift`, `gbpDiaryTests/Domain/ChatEvalTests.swift` | `workWeekday_resolvesWeekendBackToFriday`, `meetingFoldsWeekendBackToFriday`, `emailAndTaskFoldWeekendForwardToMonday`, `weekdayIsUnchanged`, `foldWork_alwaysBackToFriday`, `corpus_foldsWeekendMeetingDateToWeekday` |
| Chat lens routing: `ChatLensSelector.select` returns `.timeReport` when `wantsTimeTotals`, else `.activityDigest` for an interval-bounded recap verb, else `.openBox` | Chat / lenses | `gbpDiaryTests/Domain/ChatLensTests.swift` | `timeReport_whenWantsTimeTotals`, `activityDigest_whenIntervalBoundedRecap`, `openBox_otherwise` |
| Canonical `TimeLedger.compute`: each logged activity counts once to its own project; each standard block contributes net = max(0, capacity − in-block logged) to the block's project (overtime/evening blocks contribute no capacity); `standardTotal` = non-overtime capacity + standalone weekday work (mirrors the diary), `overtime` = evening in-block + weekend, `grandTotal`/`perProjectTotal`; per-project + `distinctWeeks` + per-block net; dedupe by source key; interval filter | Time accounting | `gbpDiaryTests/Domain/TimeLedgerTests.swift` | `inBlockActivity_attributedToOwnProject_reducesBlockNet`, `standaloneActivity_countsToProjectAndStandardTotal`, `overLoggedBlock_netZero_perProjectIsActual`, `overtime_eveningInBlockAndWeekend_notInStandardTotal`, `distinctWeeks_perProject`, `intervalFilter_dropsOutOfWindow`, `multiProjectActivity_attributesToEach_totalCountsOnce`, `dedupeBySourceKey`, `standardTotal_mirrorsDiaryFormula` |
| `TimeLedgerProjection` maps @Model → ledger inputs (blocks + activities) reusing `FocusBlockAssignment.containingBlock` (in-block vs standalone) + `WeekendPolicy` (weekend work → Friday, overtime): an in-block meeting is attributed to its own project and reduces the block's net; **an `EmailConversation` owns its logged time, attributed to the conversation's project(s)** (in-block conversation time reduces the block's net; standalone conversation time counts to its project + standard total); standalone/legacy/weekend items are handled per the diary; task-shaped (`project(conversations:)`) + diary-shaped (`projectDiary`) inputs share one code path | Time accounting | `gbpDiaryTests/Domain/TimeLedgerProjectionTests.swift` | `inBlockMeeting_attributedToOwnProject_reducesBlockNet`, `inBlockConversationTime_attributedToOwnProject_reducesBlockNet`, `standaloneConversationTime_countedToProjectAndStandardTotal`, `standaloneTaskEntry_countedOnADayWithNoBlocks`, `legacyCompletedTaskDuration_counted`, `weekendWork_foldsToFridayAndIsOvertime`, `standaloneMeeting_countedInStandardTotal` |
| Sent-email time reaches the ledger only via the conversation: `SentEmailActivityRow` logs a **conversation-linked** `TaskTimeEntry` (the conversation owns email time), so it counts in the Chat/Timesheet per-project ledger; a stray per-message email-only entry does not | Email time-logging / ledger | `gbpDiaryTests/Domain/TimeLedgerProjectionTests.swift` | `sentEmailTime_countsViaConversation_notViaPerMessageEmail` |
| Time-report lens: `ChatTimeTotals.from(ledger:projectName:)` filters the canonical `TimeLedger` result to the asked project; `report(...)` renders a deterministic answer (single-project sentence or per-project list + total) with distinct-active-weeks; `emptyReport` explains the scope/window; the pipeline answers time questions from the ledger with no model and never degrades | Chat / time report | `gbpDiaryTests/Domain/ChatTimeTotalsTests.swift`, `gbpDiaryTests/Domain/ChatEvalTests.swift` | `from_filtersToOneProject_caseInsensitive`, `report_singleProjectAndPerProject`, `emptyReport_explainsScopeAndWindow`, `authoritativeBlock_formatsFigures`, `totals_computedDeterministicallyOverInterval`, `timeReport_allTime_perProject_neverDegrades`, `followUp_inheritsPriorProjectIntervalAndKind` |
| Activity-digest lens: `ChatActivityDigestBuilder.build` keeps only in-window items (sorted); `ChatActivityDigest.render` groups by weekday and never prints a weekend; `sources` dedups; `phrasingPrompt` is a strict rephrase-only instruction; the pipeline answers a "summarise my week" from the app-built digest (folding a Saturday meeting to Friday), phrasing via the model only when available and never degrading | Chat / activity digest | `gbpDiaryTests/Domain/ChatActivityDigestTests.swift`, `gbpDiaryTests/Domain/ChatEvalTests.swift` | `build_keepsOnlyInWindowItemsSortedByDate`, `render_groupsByDayAndNeverShowsWeekend`, `empty_rendersEmptyString`, `sources_dedupById`, `phrasingPrompt_isStrictAndCarriesBlock`, `digest_summariseLastWeek_foldsWeekendAndInventsNothing`, `digest_handsModelAWeekendFreeBlock` |
| Model-driven intent (Phase 1): `ChatQuerySpecMapping.merge` refines a deterministic heuristic scope with the model's structured spec — `resolveKinds` whitelists kind tokens, `resolveProject` validates against known names (exact/containment, never a hallucination), an LM period overrides else the heuristic interval is kept, and the totals/overview flags are unioned (a heuristic-true flag is never dropped); the **project filter comes only from the heuristic** — the model may never introduce one (guarding the "list of projects" → unrelated-project over-scoping bug); `ChatDatePeriod.window` maps each period token to its interval+label (`.none` → nil). `FoundationModelsScopeResolver` merges the on-device `@Generable ChatQuerySpecDraft` over `HeuristicScopeResolver` and returns the heuristic unchanged when the model is unavailable | Chat / query-scoped retrieval | `gbpDiaryTests/Domain/ChatQuerySpecMappingTests.swift` | `period_windows`, `resolveKinds_whitelistsAndDropsUnknown`, `resolveProject_validatesAgainstKnownNames`, `merge_lmKindsOverrideEmptyHeuristic`, `merge_ignoresModelProject_projectComesFromHeuristicOnly`, `merge_lmPeriodSetsInterval_elseKeepsHeuristic`, `merge_flagsAreUnioned_neverDropHeuristicTrue`, `merge_emptyLM_returnsHeuristicUnchanged` |
| Per-project report (pure): `ProjectActivitySection.headerLine` = "Name — Xh · Yd · N weeks" (`TimeFormat.hours/days` + `ChatTimeTotals.weeksText`); `ProjectActivityReport.render()` = each section's header then `• label` bullets, sections in order (a section with no items shows just its header); `section(matching:)` is case-insensitive; `narrativeBlock(projectName:)` renders bullets grouped under each project name with no time header (nil = all sections, a named-but-unmatched project → ""); `phrasingPrompt(section:)` is strict rephrase-only | Chat + Timesheet / per-project reports | `gbpDiaryTests/Domain/ProjectActivityReportTests.swift` | `headerLine_showsHoursDaysWeeks`, `render_headerThenBullets_sectionsInOrder`, `sectionMatching_isCaseInsensitive`, `narrativeBlock_bulletsGroupedByProject_noTimeHeader_optionallyScoped`, `phrasingPrompt_isStrictRephraseOnly` |
| Per-project projection (`@MainActor`): `ProjectActivityProjection.report(interval:tasks:conversations:meetings:focusBlocks:calendar:maxEmailsPerProject:)` takes hours/distinctWeeks from `TimeLedgerProjection.ledger(...)` and gathers narrative `ChatActivityItem`s from meetings, completed tasks, logged (non-empty) task/focus-block comments, **non-empty comments on a conversation's own time entries**, and **email conversations** (`EmailConversation`, one item per conversation, importance-first, capped) under the right project with the right label/kind; every item is weekend-folded (→ Friday for work) and interval-filtered; a project with items but no logged hours still appears; blank-comment entries are skipped; the `(no project)` hours bucket is never a section | Chat + Timesheet / per-project reports | `gbpDiaryTests/Domain/ProjectActivityProjectionTests.swift` | `meetingsTasksCommentsEmails_landUnderTheRightProjectWithLabels`, `conversationTime_landsUnderConversationProjectWithComment`, `hoursAndWeeks_comeFromTheLedger`, `weekendItem_foldsToFriday`, `intervalFilter_dropsOutOfWindowItems`, `projectWithItemsButNoLoggedHours_stillAppears`, `emptyCommentEntries_areSkipped`, `emails_areImportanceFirstAndCapped`, `noProjectHoursBucket_isNotASection` |
| Chat time-report narrative: `ChatAnswerPipeline.run` takes a `projectActivity:` closure; the time-report lens appends the shared report's `narrativeBlock(projectName:)` bullets under the hours (deterministic — `prompt == nil`, no model/retrieval) | Chat / time report + narrative | `gbpDiaryTests/Domain/ChatEvalTests.swift` | `timeReport_appendsPerProjectNarrative`, `totals_computedDeterministicallyOverInterval`, `timeReport_allTime_perProject_neverDegrades` |
| Shared AI-summary voice: `AISummaryStyle.directive` encodes second person ("you") + simple past + neutral tone + no-markdown as a `• …` block (one line per `rules` entry); `inline` is a one-line second-person/simple-past/professional form; `version` ≥ 1. Every summary prompt composes from it — `EmailSummaryPrompt.instructions` (voice folded in; `promptVersion` = email base + `AISummaryStyle.version`), `ProjectActivityReport.phrasingPrompt`, and `ChatActivityDigestBuilder.phrasingPrompt` all carry the second-person/simple-past voice | AI summaries / shared voice | `gbpDiaryTests/Domain/AISummaryStyleTests.swift`, `gbpDiaryTests/Domain/EmailSummaryTests.swift`, `gbpDiaryTests/Domain/ProjectActivityReportTests.swift`, `gbpDiaryTests/Domain/ChatActivityDigestTests.swift`, `gbpDiaryTests/Domain/ChatEvalTests.swift` | `directive_encodesSecondPersonSimplePastNeutralNoMarkdown`, `inline_isOneLineSecondPersonSimplePast`, `version_isPositive`, `instructions_containKeyRules`, `promptVersion_reflectsPerspectiveAndIdiomRules`, `phrasingPrompt_isStrictRephraseOnly`, `phrasingPrompt_isStrictAndCarriesBlock`, `digest_handsModelAWeekendFreeBlock` |

| Quoted-history stripping: `EmailQuotedHistory.newestMessage` returns the body above the first quoted-history boundary (`On … wrote:` incl. wrapped, `-----Original Message-----`/`Forwarded message` dividers, ≥10-char underscore separators, and `From:` blocks with a nearby `Sent:/Date:` + `To:`); a sentence merely ending "wrote:" and a bare prose "From:" are not cut; no boundary or a body quoted from line 0 returns the body unchanged; `EmailSummaryPrompt.build` applies it (so quoted history never reaches the model) and `emailPromptBase` = 3 to refresh the backlog | On-device email summaries / thread history | `gbpDiaryTests/Domain/EmailQuotedHistoryTests.swift`, `gbpDiaryTests/Domain/EmailSummaryTests.swift` | `gmailAttribution_keepsOnlyNewestMessage`, `wrappedAttribution_backsUpToTheOnLine`, `outlookOriginalMessageDivider_isCut`, `forwardedMessageBanner_isCut`, `outlookUnderscoreSeparator_isCut`, `quotedHeaderBlock_requiresSentAndTo`, `sentenceEndingInWrote_isNotCut`, `noBoundary_returnsBodyUnchanged`, `bodyQuotedFromStart_returnsUnchanged`, `emptyBody_isEmpty`, `prompt_stripsQuotedHistoryFromBody` |

| Calendar access on first grant: `CalendarService.resolve(granted:fallback:)` returns `.authorized` whenever EventKit reports `granted` (authoritative right after approval, when `authorizationStatus` may still read `.notDetermined`), else the fallback status — so the meeting-import list populates immediately after approval | Calendar import / access | `gbpDiaryTests/Domain/CalendarAccessTests.swift` | `resolve_grantedIsAuthoritative`, `resolve_notGranted_usesFallback` |

| Email thread grouping: `EmailThreadBuilder.threads(from:)` groups emails by `EmailThreading.threadKey` (normalized subject + party = resolved Person id else `fromAddress`) so a conversation's sent + received messages unite (Sent stores the recipient), messages sort latest-first, and `EmailThread.sentCount`/`receivedCount` reflect the split; different party/subject split into separate threads. (Superseded in the views by the persistent `EmailConversation` entity; the pure helper + tests remain) | Email threads / helper | `gbpDiaryTests/Domain/EmailThreadBuilderTests.swift` | `conversationUnitesSentAndReceived`, `differentPartyOrSubjectSplits`, `partyMatchesByResolvedPersonAcrossAddresses` |
| Whole-thread day summary (synthesized): `EmailThreadSummaryPrompt.build` embeds subject/participants + each message as "(sent/received <time>) <summary>" and carries the shared `AISummaryStyle` voice; `promptVersion` = base + `AISummaryStyle.version`; `EmailThreadSummaryFingerprint.make` is order-independent and changes when a member joins/leaves or re-summarises; `EmailThreadSummaryPlanning.needsSummary` is true when missing/stale/changed and false when settled (done/failed) with a matching fingerprint + current version | Email threads / on-device summary | `gbpDiaryTests/Domain/EmailThreadSummaryTests.swift` | `prompt_embedsDirectionsSummariesAndSharedVoice`, `promptVersion_foldsSharedStyleVersion`, `fingerprint_changesOnMemberOrVersionChange`, `needsSummary_trueWhenMissingStaleOrChanged_falseWhenCurrent` |
| Reply-chain header import: `MailScriptParsing` reads the RFC `message id` + `In-Reply-To` + `References` per message (Mail `header whose name is …`), extends `MailMessageDraft` (`rfcMessageId`/`inReplyTo`/`references`, bare), and `parseOutput` parses the 13-field record (backward-compatible with 10-field); `parseMessageIds` extracts `<…>` tokens bare, `normalizeMessageId` strips brackets | Email threading / reply-chain | `gbpDiaryTests/Domain/MailScriptParsingTests.swift` | `parseOutput_parsesReplyChainHeaders`, `parseOutput_oldTenFieldRecordStillParses`, `parseMessageIds_extractsBareTokens` |
| Reply-graph threading: `EmailThreadGraph.assign` groups messages by the reply graph (union-find over Message-ID/In-Reply-To/References) with a stable min-id `threadKey` per component, subject fallback for headerless messages; reply chains + subject-changes + multi-party unite, recurring subjects with their own ids stay separate, and assignment is order-independent | Email threading / reply-chain | `gbpDiaryTests/Domain/EmailThreadGraphTests.swift` | `replyChainUnites`, `subjectChangeMidThreadStaysOneThread`, `multiPartyExchangeUnites`, `recurringSubjectWithoutLinksStaysSeparate`, `headerlessFallsBackToSubject`, `assignmentIsDeterministicRegardlessOfOrder` |
| Conversation state fold: `EmailThreadFold.fold` rolls member `(accepted, dismissed, importance)` up to the conversation — any unclassified member → to-triage; else any accepted → accepted; else all-dismissed → dismissed; importance = max; empty → unclassified/low | Email conversations / migration | `gbpDiaryTests/Domain/EmailThreadFoldTests.swift` | `anyUnclassifiedKeepsConversationToTriage`, `anyAcceptedWhenNoneUnclassified`, `allDismissed`, `importanceIsMaxAcrossMembers`, `emptyIsUnclassifiedLow` |
| Conversation reconcile (`@MainActor`, ingest + one-time migration): `EmailConversationReconciler.reconcile` groups emails by `EmailThreadGraph`, ensures one `EmailConversation` per group (sticky — an email keeps its conversation so user state survives), links new mail to an existing conversation without overwriting its state, merges conversations bridged by a later reply, and folds legacy per-message state (projects/person/importance/triage/time) onto newly-created conversations | Email conversations / entity | `gbpDiaryTests/Domain/EmailConversationReconcilerTests.swift` | `replyGraphGroupsIntoOneConversation_otherSubjectSeparate`, `foldsLegacyStateOntoConversation`, `anyUnclassifiedMemberKeepsConversationToTriage`, `newReplyJoinsExistingConversationWithoutOverwritingState`, `bridgingReplyMergesTwoConversations` |
| Junk mail excluded: the fetch carries Mail's `junk mail status` per Inbox message (`MailScriptParsing` → `MailMessageDraft.isJunk`, parsed from the record's 14th field); `EmailIngest.upsert` skips new junk (never ingested) and **dismisses an already-stored copy** whose draft is now junk-flagged (self-heal) | Email ingest / junk | `gbpDiaryTests/Domain/MailScriptParsingTests.swift`, `gbpDiaryTests/Domain/EmailIngestJunkTests.swift` | `parseOutput_parsesJunkFlag`, `script_containsDayBoundsAccountAndMailboxes` (asserts `junk mail status`/`isJunk`), `junkDraftDismissesTheStoredCopy`, `newJunkIsNotIngested`, `nonJunkStillIngests` |

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
