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
  ├── Day tab    → DayView(date:)
  ├── Week tab   → WeekView(weekOf:)
  ├── Timesheet  → TimesheetView()
  ├── Projects   → ProjectsView()  [NavigationSplitView internally]
  └── People     → PeopleView()    [NavigationSplitView internally]
```

### Data layer

All persistence is SwiftData. Models live in `gbpDiary/Models/`. The `ModelContainer` is created in `gbpDiaryApp` and injected via `.modelContainer()`.

**Task is the canonical domain object.** Tasks are identity-stable across all views. They do not "belong" to a day via a stored list — they appear in day sections through date predicate queries on `scheduledAt` and `completedAt`.

### Day view sections (query logic, in `DayView`)

| Section | Filter |
|---------|--------|
| Scheduled | `scheduledAt` in `[dayStart, dayEnd)` AND `status == .open` |
| Follow-ups Due | `followUpAt < dayEnd` AND `status == .followUpPending` |
| Backlog | `status == .open` AND `parent == nil` AND (`scheduledAt == nil` OR `scheduledAt < dayStart`) |
| Completed Today | `completedAt` in `[dayStart, dayEnd)` |

All four use `@Query(sort: \Task.createdAt) var allTasks` filtered in-memory. This is intentional: the task list for a personal app stays small, and SwiftData predicate support for complex enum/date combinations is easier to read in-memory.

---

## Data model

Value types (Codable structs, not `@Model`) in `Models/ValueTypes.swift`:
- `TaskStatus`: `open | completed | cancelled | followUpPending`
- `DurationUnit`: `h | d | w` (hours / days≈7.6h / weeks≈38h)
- `Duration`: `value + unit + hoursNormalized`. Use `Duration.parse("1.5h")` for user input.
- `SourceContext`: import provenance metadata (not used by UI, preserved for import pipeline)

`@Model` entities and their key relationships:

```
Task
  assignee → Person?
  project  → Project?
  minutes  → Minutes?
  originDay→ DayRecord?      (where captured; not the day-view link)
  parent   → Task?
  children → [Task]          cascade delete

DayRecord                    (date, notes?, focusTags[])
                             No stored Task list — queried by date

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
  projects  → [Project]  ↔ Project.meetings
  attendees → [Person]   ↔ Person.minutesAttended

Document
  attachments → [Attachment]  cascade delete ↔ Attachment.document
  projects    → [Project]     ↔ Project.documents

Attachment     (fileURL + bookmarkData for sandbox persistence)
  document → Document?

Note           (standalone, not yet wired into UI)
```

Each `@Model` has `@Attribute(.unique) var id: UUID` for stable external identity (used by the import pipeline). SwiftData also assigns its own `persistentModelID`.

---

## Key conventions

### Swift 6 / strict concurrency

All types are implicitly `@MainActor` (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`). Model mutations happen synchronously on the main actor. Use `Swift.Task { }` (module-qualified) when you need a concurrency task in files that also reference the `Task` model.

### Adding new files

Just create the `.swift` file in the right directory — Xcode picks it up automatically. Suggested locations:
- New model → `gbpDiary/Models/`
- New view for an existing tab → `gbpDiary/Views/<TabName>Tab/`
- Shared UI component → `gbpDiary/Views/` (top level of Views)

### Querying

Prefer `@Query` at the top of a view for simple sorts/filters. For dynamic filters (e.g., date changes as user navigates), use `@Query(sort:)` to fetch all and filter in a computed property. Avoid `#Predicate` with enum comparisons until verified — in-memory filtering is fast enough for personal data volumes.

### Task state transitions

All transitions are in `Task` extension methods (`markCompleted()`, `unmarkCompleted()`, `markCancelled()`, `unmarkCancelled()`, `setFollowUp(date:)`, `markFollowUpDone()`, `setDuration(_:)`). Call these methods from views; do not mutate `status`, `completedAt`, `cancelledAt`, or `followUpAt` directly.

The full state transition table is in the handoff spec (`/Users/gbpoole/swift_app_handoff_spec.md`, section 3).

### Duration

User input is a string like `"1.5h"`, `"2d"`, `"1w"`. Parse with `Duration.parse(_:)` — returns `nil` on invalid input. Always display with `duration.displayString`. Store `hoursNormalized` for all timesheet arithmetic.

### Shared UI components

- `Chip(label:color:)` — pill label for project/person/tag/duration metadata. Defined in `TaskRowView.swift`.
- `FlowLayout` — wrapping HStack-like layout. Defined in `MinutesDetailView.swift`.
- `TaskRowView` — recursive: renders a task and its `children` indented below. Used in DayView, ProjectDetailView, PersonDetailView.
- `TaskEditorSheet` — full task editing sheet. Accepts `task: Task?` (nil = create new) and `defaultDate: Date`.

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
- **Document creation UI**: `DocumentDetailView` exists but no way to create a `Document` record yet.
- **`DayRecord` notes editor**: model has `notes` and `focusTags` fields, not exposed in UI.
- **Timesheet hierarchy validation**: child duration > parent duration warning.
