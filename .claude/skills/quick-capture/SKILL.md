---
name: quick-capture
description: Read before working on the gbpdiary:// capture URL scheme, the QuickCaptureView, TaskSource provenance, or the Alfred/Shortcuts capture recipes.
---

# Quick capture (`gbpdiary://`) + source-linked tasks

Capture a task from anywhere with its **source** attached, without switching to the app first.

## The URL contract
`gbpdiary://task?title=<text>&kind=<email|slack|web|other>&url=<deep link>&mailId=<Mail id>`
- Parsed by the pure `CaptureURL.parse` (`Domain/CaptureURL.swift`); needs at least a `title`, `url`, or `mailId`.
- `gbpDiaryApp.onOpenURL` → presents **`QuickCaptureView`** (`Views/Capture/QuickCaptureView.swift`): prefilled
  summary + optional project/due. **Add** creates a `Task` that **always lands in the Inbox** (`needsTriage`) with
  a first-class **`TaskSource`** (`Models/TaskSource.swift`; kind + url + title + optional `EmailMessage`).
- Registered via `gbpDiary-Info.plist` (`CFBundleURLTypes`, scheme `gbpdiary`) + `INFOPLIST_FILE` on the app
  target's two build configs (the project otherwise uses `GENERATE_INFOPLIST_FILE`).
- Test it with: `open "gbpdiary://task?kind=web&title=Try%20me&url=https://example.com"`.

## Provenance model
`Task.source: TaskSource?` (cascade). For email, `TaskSource.email` links the rich `EmailMessage` (summary/
importance/thread), and `Task.originEmail` remains the email inverse backbone (email tasks carry both). The task
row shows a source-kind glyph; `TaskDetailView` shows a **Source** chip that opens the link (web/slack via
`openURL`) or the message in Mail (`MailScriptService.openMessage`). Email `mailId` resolves to an `EmailMessage`
by matching `EmailMessage.messageId`.

## Alfred recipes (driver — pluggable; Shortcuts or raw `open` also work)
- **Mail (frictionless):** Alfred hotkey → Run AppleScript
  `tell application "Mail" to set m to item 1 of (get selection)` → read `subject` and `id of m` →
  `open location "gbpdiary://task?kind=email&mailId=" & (id of m) & "&title=" & (encoded subject)`.
  No manual copy-link; the app links the ingested message (or a stub if outside the ~3-day fetch window).
- **Web:** Alfred grabs the front browser URL + title → `kind=web&url=…&title=…`.
- **Slack (DEFERRED — not built):** Slack has no AppleScript API. When chosen, either an Alfred workflow
  (Copy link on the message → validate the clipboard is a `slack.com/archives/…` permalink, else notify "Copy the
  Slack message link first" → prompt title → `kind=slack&url=<permalink>`; the app adds a `SlackLink` validator,
  a duplicate-guard, and on-success clipboard clear), **or** a networked Slack Web API connector (OAuth) — an open
  strategic choice. The Phase-1/2 core is agnostic to which.

## Status
- **Built:** `TaskSource` + migration, `gbpdiary://` scheme + `QuickCaptureView`, Mail/web capture, Source
  chip/glyph, duplicate-URL warning.
- **Not built:** Slack mechanism; generalizing the Tasks "From email" filter into slack/web source filters.
