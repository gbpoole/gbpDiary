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
  ├── Tasks tab     → TasksView()         [filterable global task table]
  ├── Week tab      → WeekView(weekOf:)
  ├── Timesheet     → TimesheetView()
  ├── Projects      → ProjectsView()      [NavigationSplitView internally]
  ├── People        → PeopleView()        [NavigationSplitView internally]
  ├── Minutes       → MinutesListView()   [NavigationSplitView internally]
  └── Documents     → DocumentsListView() [NavigationSplitView internally]
```

### Data layer

All persistence is SwiftData. Models live in `gbpDiary/Models/`. The `ModelContainer` is created in `gbpDiaryApp` and injected via `.modelContainer()`.

**Task is the canonical domain object.** Tasks are identity-stable across all views. They do not "belong" to a day via a stored list — they appear in day sections through date predicate queries on `scheduledAt` and `completedAt`.

### Day view architecture

The Day tab renders a `DayPageContent` view with four typed sections. Meetings are the only diary `DayEntry` blocks still used; tasks are anchored directly to a `DayRecord` via `Task.dayRecord`.

```
DayPageContent
  └── ScrollView
        └── VStack
              ├── dayNoteSection      MarkdownEditorSection bound to DayRecord.notes
              ├── meetingsSection     EntryRowView (kind == .meeting) per DayEntry
              ├── newTasksSection     DiaryTaskRow per Task with dayRecord == thisRecord
              ├── completedTasksSection  CompletedTaskRow for tasks completedAt in day
              ├── documentsSection    DayDocumentRow per Document.dayRecord == thisRecord
              └── sidebarSections     (Scheduled + Inbox; hidden when showTaskSections == false)
```

Old `DayEntry(kind:.note)` entries are auto-migrated into `DayRecord.notes` the first time each day is opened (`migrateOldNotes()` called on `.onAppear`).

### Day view sections (inline and sidebar)

| Section | Location | Filter |
|---------|----------|--------|
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
- `DurationUnit`: `h | d | w` (hours / days≈7.6h / weeks≈38h)
- `Duration`: `value + unit + hoursNormalized`. Use `Duration.parse("1.5h")` for user input.
- `SourceContext`: import provenance metadata (not used by UI, preserved for import pipeline)

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
  NOTE: Task no longer has a `minutes` relationship.

DayEntry                     (a single diary block for one day)
  kind      : DayEntryKind   (.note | .task | .meeting)
  text      : String         (note content; unused for task/meeting)
  sortOrder : Int            (display order within the day)
  indentLevel: Int           (0–6; visual indent in 20pt steps)
  task     → Task?           (set when kind == .task)
  minutes  → Minutes?        (set when kind == .meeting)
  dayRecord→ DayRecord?

DayRecord                    (date, notes?, focusTags[])
  entries  → [DayEntry]      (cascade delete; only meeting kind used now)
  tasks    → [Task]          (nullify on delete; "new tasks" for this day)
  documents→ [Document]      (nullify on delete)

Project
  parent       → Project?
  subprojects  → [Project]   nullify on parent delete
  devTeam      → [Person]    ↔ Person.devProjects
  sciTeam      → [Person]    ↔ Person.sciProjects
  institutions → [Institution] ↔ Institution.projects
  meetings     → [Minutes]   ↔ Minutes.projects
  documents    → [Document]  ↔ Document.projects

Person
  institution    → Institution?  ↔ Institution.members
  devProjects    → [Project]
  sciProjects    → [Project]
  minutesAttended→ [Minutes]

Institution
  members  → [Person]   ↔ Person.institution
  projects → [Project]

Minutes
  summary   : String?        (one-line summary; editable inline in diary)
  newTasks  → [Task]     ↔ Task.originMinutes  (nullify on delete)
  projects  → [Project]  ↔ Project.meetings
  attendees → [Person]   ↔ Person.minutesAttended

Document
  summary     : String?
  attachments → [Attachment]  cascade delete ↔ Attachment.document
  projects    → [Project]     ↔ Project.documents
  dayRecord  → DayRecord?     (set when captured from a day's Documents section)

Attachment     (fileURL + bookmarkData for sandbox persistence)
  document → Document?

Note           (standalone, not yet wired into UI)
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

Status cycle (via tap on status icon in `TaskRowView`): `.todo` → `.started` → `.completed`. Long-press / context menu provides access to cancel, follow-up, and reopen.

The full state transition table is in the handoff spec (`/Users/gbpoole/swift_app_handoff_spec.md`, section 3).

### Duration

User input is a string like `"1.5h"`, `"2d"`, `"1w"`. Parse with `Duration.parse(_:)` — returns `nil` on invalid input. Always display with `duration.displayString`. Store `hoursNormalized` for all timesheet arithmetic.

### Meeting entries

When a meeting `DayEntry` is created, `addMeeting()` automatically creates and links a `Minutes` object. Deleting a meeting entry requires confirmation (alert) because it also deletes the linked `Minutes`. The meeting's one-line summary is stored on `Minutes.summary` and edited inline in the diary row.

### Shared UI components

- `Chip(label:color:)` — pill label for project/person/tag/duration metadata. Defined in `TaskRowView.swift`.
- `FlowLayout` — wrapping HStack-like layout. Defined in `MinutesDetailView.swift`.
- `TaskRowView` — renders a task row. Used in DayView sidebar, TasksView, ProjectDetailView, PersonDetailView. Supports `inlineEditing: Bool`.
- `DiaryTaskRow` — renders a root day-task (Task with dayRecord set) with inline editing, notes sub-area, collapse/expand, and subtask tree.
- `TaskEditorSheet` — full task editing sheet. Accepts `task: Task?` (nil = create new) and `defaultDate: Date`.
- `EntryRowView` — renders a meeting `DayEntry` with inline summary, minutes notes sub-area, and embedded New Tasks subtree. (Note/task DayEntry kinds are no longer rendered.)
- `DayTaskSidebar` — collapsible sidebar with Scheduled and Inbox sections for a given day.
- `DaySectionHeader` — reusable section header with title and optional "+" button.
- `CompletedTaskRow` — read-only struck-through task row with completion time; tap opens `TaskEditorSheet`.
- `DayDocumentRow` — one-line document row (icon + summary) in the day's Documents section.
- `TasksView` — filterable macOS Table (or List on iOS) of all tasks. Filter controls in `TasksFilterBar`.
- `MinutesDetailView(minutes:asSheet:)` — detail view for a `Minutes` record; pass `asSheet: true` when presenting as a sheet.
- `DocumentDetailView(document:asSheet:)` — same pattern for `Document`.

### macOS-specific: DeleteKeyMonitor

`onKeyPress(.delete)` cannot intercept ⌫ inside a `TextField` because `NSTextField.deleteBackward:` fires inside `interpretKeyEvents:` before SwiftUI's handler runs. `DeleteKeyMonitor` uses `NSEvent.addLocalMonitorForEvents(matching: .keyDown)` to intercept at the event level. It is started/stopped in `.onAppear`/`.onDisappear` of `DayPageContent`. The action closure checks whether the focused entry is empty before deleting — use a kind-aware check (`task.summary`, `minutes.summary`, `entry.text`) not a generic `entry.text` check.

### macOS SwiftUI quirk: `.alert()` and layout padding

On macOS, applying `.alert()` in the outer modifier chain of a block view (outside `.background()` / `.clipShape()` but alongside `.padding(.horizontal)`) silently collapses the padding's layout proposal, producing ~0pt margin. **Fix:** apply `.alert()` at the `body` level (or inside the inner content chain, before `.background()`), not after the outer layout padding. This does not affect note or task blocks since they use only `.sheet()` or `.contextMenu()` in the outer chain.

### SwiftUI quirk: `LazyVStack` + nested `ScrollView` → infinite layout loop

Do **not** place a view that contains a `ScrollView` inside a `LazyVStack`. `LazyVStack`'s lazy measurement algorithm re-proposes heights as cells scroll into view; if the nested `ScrollView` (or any `NSViewRepresentable` inside it, such as `StructuredText` or `TextEditor`) reports a slightly different size between passes, SwiftUI enters an infinite measure → invalidate → re-measure cycle. Each pass allocates new view descriptors, producing unbounded memory growth and 100 % CPU. **Fix:** use a plain `VStack` instead. For sections bounded in number (e.g., 7 days in `WeekView`) the performance difference is negligible. `DayPageContent` contains a nested `ScrollView`, so any container that holds multiple `DayPageContent` instances must use `VStack`, not `LazyVStack`.

### Platform guards

Use `#if os(macOS)` for macOS-specific sizing (`.frame(minWidth:minHeight:)` on sheets) and for toolbar item placements. The iOS tab bar and edit button are not yet wired — leave `#if os(iOS)` blocks as stubs.

---

## What is not yet built

- **Import pipeline**: bootstrap from Obsidian vault. Pseudocode spec in `/Users/gbpoole/swift_app_handoff_spec.md` section 4.
- **Tasks dashboard**: tasks grouped by person + project with age/data-quality diagnostics.
- **iCloud sync**: add `cloudKitContainerIdentifier` to `ModelConfiguration` when ready.
- **iPhone UI**: Day screen as home with fast capture loop.
- **Schema migration**: versioned SwiftData migration stages for future model changes.
- **Note entity**: model exists, no UI yet.
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
| Task markCancelled sets status/cancelledAt (idempotent — only sets if nil); preserves completedAt | Task state transitions | gbpDiaryTests/Models/TaskStateTransitionTests.swift | `markCancelled_setsExpectedFields`, `markCancelled_preservesExistingCancelledAt`, `markCancelled_preservesExistingCompletedAt` |
| Cycling through all states preserves original timestamps (e.g., completedAt survives completed→followUp→cancelled→todo→completed) | Task state transitions | gbpDiaryTests/Models/TaskStateTransitionTests.swift | `cycling_preservesOriginalCompletedAt` |
| Duration parsing + normalization (`h/d/w`) | Duration | gbpDiaryTests/Models/DurationTests.swift | `parse_validInputs_normalizesHours`, `parse_invalidInputs_returnsNil` |
| Timesheet includes only completed tasks with duration in selected interval | Timesheet | gbpDiaryTests/Domain/TimesheetComputationTests.swift | `tasksInRange_requiresCompletedAtAndDuration` |
| Scheduled filter uses `scheduledAt` in `[dayStart, dayEnd)` and todo/started status | Day view sections | gbpDiaryTests/Domain/DayTaskFilteringTests.swift | `scheduled_requiresTodoOrStartedAndWithinDayBounds`, `scheduled_excludesTasksAlreadyInEntries` |
| Inbox filter: status todo/started, parent == nil, project == nil, assignee == nil | Day view sidebar | gbpDiaryTests/Domain/DayTaskFilteringTests.swift | `inbox_includesUnassignedTopLevelActiveTasks`, `inbox_includesStartedButExcludesOtherStatuses` |
| notesId derives a stable focus ID by bit-complementing all 16 UUID bytes; result is its own inverse and never collides with organic UUIDs | Inline task notes / meeting minutes | gbpDiaryTests/Models/DayEntryContentTests.swift | (tested indirectly via `notesAreaFocusId` usage) |

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
