#!/usr/bin/env python3
"""A read-only MCP server over the gbpDiary SwiftData store.

Lets a local agent (opencode + Ollama, or any MCP client) interrogate the diary's content without
knowing anything about Core Data's storage. The raw store is hostile to query blind: tables are
Z-prefixed (ZTASK, ZMINUTES), dates are Core Data epoch (+978307200), a Duration is split across
ZVALUE/ZUNIT/ZHOURSNORMALIZED, and many-to-many links live in join tables with columns like
Z_10MEETINGS1/Z_13PROJECTS4. This server hides all of that behind readable SQL views.

Design constraints, deliberately:

* READ-ONLY. The connection is opened `mode=ro` and only a single SELECT/WITH statement is accepted.
  Writing from outside the app would bypass every invariant SwiftData maintains (needsTriage,
  updatedAt, the meeting-day anchor, relationship inverses) and risk the store while the app holds it.
* NO TIME ACCOUNTING. Hours in this store are raw records, not the app's reported time. The canonical
  rules (focus-block net = capacity − in-block logged, weekend work folded to Friday, meetings split by
  slot overlap, dedupe by source key, conversation-owned email time) live in Swift (TimeLedger /
  TimeLedgerProjection / TimesheetProjection). SUM(hours) here will NOT match the Timesheet, so the
  tools say so loudly rather than inviting a confidently wrong answer.
* Stdlib only, single file — nothing to install, nothing to keep in sync.

Protocol: MCP over stdio, newline-delimited JSON-RPC 2.0 (initialize / tools/list / tools/call / ping).
"""

from __future__ import annotations

import json
import os
import re
import sqlite3
import subprocess
import sys

# Core Data stores timestamps as seconds since 2001-01-01.
APPLE_EPOCH_OFFSET = 978307200

DEFAULT_STORE = os.path.expanduser(
    "~/Library/Containers/io.github.gbpoole.gbpDiary/Data/Library/"
    "Application Support/default.store"
)


# Exports go only where the user chose, so nothing accumulates in the app container. The app records the
# path of the JSON it last wrote; this is how an external reader finds it.
LEGACY_SNAPSHOT = os.path.expanduser(
    "~/Library/Containers/io.github.gbpoole.gbpDiary/Data/Library/"
    "Application Support/Exports/timesheet-latest.json"
)
APP_DEFAULTS_DOMAIN = "io.github.gbpoole.gbpDiary"


def _recorded_snapshot_path():
    """The JSON written by the app's most recent Timesheet export, from its own preferences."""
    try:
        out = subprocess.run(["defaults", "read", APP_DEFAULTS_DOMAIN, "timesheet.lastExportPath"],
                             capture_output=True, text=True, timeout=5)
    except Exception:
        return None
    path = out.stdout.strip()
    return path if path and os.path.exists(path) else None


def resolve_snapshot(explicit=None):
    """explicit argument -> environment override -> the app's recorded export -> the legacy fixed path."""
    for candidate in (explicit,
                      os.environ.get("GBPDIARY_TIMESHEET_SNAPSHOT"),
                      _recorded_snapshot_path(),
                      LEGACY_SNAPSHOT):
        if candidate and os.path.exists(os.path.expanduser(candidate)):
            return os.path.expanduser(candidate)
    return None

TIME_WARNING = (
    "TIME WARNING: hours in these views are RAW records. The app's reported time (the Timesheet) "
    "applies rules this database does not encode — focus-block net (capacity minus in-block logged "
    "time), weekend work folded back to Friday, meetings split across blocks by slot overlap, "
    "de-duplication by source key, and email time owned by the conversation. Do NOT sum hours here "
    "and present it as time spent; it will disagree with the app. Report raw records as raw records. "
    "For time spent, call `timesheet_report` instead — it carries the app's own computed figures."
)

def _uuid(column: str) -> str:
    """SwiftData stores each model's `@Attribute(.unique) id` as a 16-byte BLOB in canonical UUID byte
    order (verified against a known id), so hex-split it back into the UUID string the app shows."""
    h = f"hex({column})"
    return (f"lower(substr({h},1,8)||'-'||substr({h},9,4)||'-'||substr({h},13,4)"
            f"||'-'||substr({h},17,4)||'-'||substr({h},21,12))")


# Readable views over the Core Data tables. Dates become local 'YYYY-MM-DD HH:MM' text; relationships
# become names; many-to-many links become comma-joined lists.
VIEWS = {
    "projects": f"""
        SELECT {_uuid('p.ZID')} AS id, p.ZNAME AS name, p.ZSTREAM AS stream,
               p.ZPROJECTDESCRIPTION AS description,
               CASE p.ZISCOMPLETED WHEN 1 THEN 'completed' ELSE 'active' END AS status,
               (SELECT par.ZNAME FROM ZPROJECT par WHERE par.Z_PK = p.ZPARENT) AS parent,
               (SELECT COUNT(*) FROM ZPROJECT c WHERE c.ZPARENT = p.Z_PK) AS subproject_count,
               p.ZTAGSJSON AS tags_json,
               datetime(p.ZTASKSREVIEWEDAT + {APPLE_EPOCH_OFFSET}, 'unixepoch', 'localtime') AS tasks_reviewed_at,
               p.Z_PK AS pk
        FROM ZPROJECT p
    """,
    "tasks": f"""
        SELECT {_uuid('t.ZID')} AS id, t.ZSUMMARY AS summary, t.ZSTATUS AS status,
               t.ZPRIORITYRAW AS priority, t.ZPLANHORIZONRAW AS plan_horizon,
               CASE t.ZNEEDSTRIAGE WHEN 1 THEN 1 ELSE 0 END AS needs_triage,
               CASE t.ZISSTANDING WHEN 1 THEN 1 ELSE 0 END AS is_standing,
               (SELECT p.ZNAME FROM ZPROJECT p WHERE p.Z_PK = t.ZPROJECT) AS project,
               (SELECT pe.ZNAME FROM ZPERSON pe WHERE pe.Z_PK = t.ZASSIGNEE) AS assignee,
               (SELECT par.ZSUMMARY FROM ZTASK par WHERE par.Z_PK = t.ZPARENT) AS parent_task,
               datetime(t.ZCREATEDAT + {APPLE_EPOCH_OFFSET}, 'unixepoch', 'localtime') AS created_at,
               datetime(t.ZDUEAT + {APPLE_EPOCH_OFFSET}, 'unixepoch', 'localtime') AS due_at,
               datetime(t.ZSCHEDULEDAT + {APPLE_EPOCH_OFFSET}, 'unixepoch', 'localtime') AS scheduled_at,
               datetime(t.ZCOMPLETEDAT + {APPLE_EPOCH_OFFSET}, 'unixepoch', 'localtime') AS completed_at,
               datetime(t.ZFOLLOWUPAT + {APPLE_EPOCH_OFFSET}, 'unixepoch', 'localtime') AS follow_up_at,
               t.ZRECURRENCERULE AS recurrence_rule, t.ZNOTES AS notes, t.ZTAGSJSON AS tags_json,
               t.Z_PK AS pk
        FROM ZTASK t
    """,
    "meetings": f"""
        SELECT {_uuid('m.ZID')} AS id, m.ZSUMMARY AS summary,
               datetime(m.ZMEETINGAT + {APPLE_EPOCH_OFFSET}, 'unixepoch', 'localtime') AS meeting_at,
               m.ZHOURSNORMALIZED AS duration_hours_raw,
               (SELECT group_concat(p.ZNAME, ', ') FROM Z_10PROJECTS j
                  JOIN ZPROJECT p ON p.Z_PK = j.Z_13PROJECTS4
                 WHERE j.Z_10MEETINGS1 = m.Z_PK) AS projects,
               (SELECT group_concat(pe.ZNAME, ', ') FROM Z_10ATTENDEES j
                  JOIN ZPERSON pe ON pe.Z_PK = j.Z_12ATTENDEES
                 WHERE j.Z_10MINUTESATTENDED = m.Z_PK) AS attendees,
               (SELECT COUNT(*) FROM Z_10ATTENDEES j WHERE j.Z_10MINUTESATTENDED = m.Z_PK) AS attendee_count,
               (SELECT n.ZCONTENT FROM ZNOTE n WHERE n.ZMINUTES = m.Z_PK) AS minutes_markdown,
               m.Z_PK AS pk
        FROM ZMINUTES m
    """,
    "time_entries": f"""
        SELECT {_uuid('e.ZID')} AS id,
               datetime(e.ZDATE + {APPLE_EPOCH_OFFSET}, 'unixepoch', 'localtime') AS date,
               e.ZHOURSNORMALIZED AS hours_raw, e.ZCOMMENT AS comment,
               (SELECT t.ZSUMMARY FROM ZTASK t WHERE t.Z_PK = e.ZTASK) AS task,
               (SELECT p.ZNAME FROM ZPROJECT p JOIN ZTASK t ON t.ZPROJECT = p.Z_PK
                 WHERE t.Z_PK = e.ZTASK) AS task_project,
               (SELECT c.ZTHREADKEY FROM ZEMAILCONVERSATION c WHERE c.Z_PK = e.ZCONVERSATION) AS conversation,
               e.Z_PK AS pk
        FROM ZTASKTIMEENTRY e
    """,
    "focus_blocks": f"""
        SELECT {_uuid('b.ZID')} AS id,
               date(d.ZDATE + {APPLE_EPOCH_OFFSET}, 'unixepoch', 'localtime') AS day,
               b.ZSLOTRAW AS slot, b.ZHOURSNORMALIZED AS capacity_hours, b.ZCOMMENT AS comment,
               (SELECT t.ZSUMMARY FROM ZTASK t WHERE t.Z_PK = b.ZTASK) AS task,
               (SELECT p.ZNAME FROM ZPROJECT p WHERE p.Z_PK = COALESCE(
                    b.ZPROJECT, (SELECT t.ZPROJECT FROM ZTASK t WHERE t.Z_PK = b.ZTASK))) AS project,
               b.Z_PK AS pk
        FROM ZFOCUSBLOCK b LEFT JOIN ZDAYRECORD d ON d.Z_PK = b.ZDAYRECORD
    """,
    "notes": f"""
        SELECT {_uuid('n.ZID')} AS id, n.ZTITLE AS title, n.ZCONTENT AS content, n.ZTAGSJSON AS tags_json,
               (SELECT p.ZNAME FROM ZPROJECT p WHERE p.Z_PK = n.ZPROJECT) AS project,
               (SELECT m.ZSUMMARY FROM ZMINUTES m WHERE m.Z_PK = n.ZMINUTES) AS meeting,
               date(d.ZDATE + {APPLE_EPOCH_OFFSET}, 'unixepoch', 'localtime') AS day,
               datetime(n.ZUPDATEDAT + {APPLE_EPOCH_OFFSET}, 'unixepoch', 'localtime') AS updated_at,
               n.Z_PK AS pk
        FROM ZNOTE n LEFT JOIN ZDAYRECORD d ON d.Z_PK = n.ZDAYRECORD
    """,
    "people": f"""
        SELECT {_uuid('pe.ZID')} AS id, pe.ZNAME AS name, pe.ZEMAILSJSON AS emails_json,
               (SELECT i.ZNAME FROM ZINSTITUTION i WHERE i.Z_PK = pe.ZINSTITUTION) AS institution,
               pe.ZTAGSJSON AS tags_json,
               (SELECT group_concat(p.ZNAME, ', ') FROM Z_12DEVPROJECTS j
                  JOIN ZPROJECT p ON p.Z_PK = j.Z_13DEVPROJECTS WHERE j.Z_12DEVTEAM = pe.Z_PK) AS dev_projects,
               (SELECT group_concat(p.ZNAME, ', ') FROM Z_12SCIPROJECTS j
                  JOIN ZPROJECT p ON p.Z_PK = j.Z_13SCIPROJECTS WHERE j.Z_12SCITEAM = pe.Z_PK) AS sci_projects,
               (SELECT COUNT(*) FROM Z_10ATTENDEES j WHERE j.Z_12ATTENDEES = pe.Z_PK) AS meetings_attended,
               pe.Z_PK AS pk
        FROM ZPERSON pe
    """,
    "institutions": f"""
        SELECT {_uuid('i.ZID')} AS id, i.ZNAME AS name,
               (SELECT COUNT(*) FROM ZPERSON pe WHERE pe.ZINSTITUTION = i.Z_PK) AS member_count,
               i.Z_PK AS pk
        FROM ZINSTITUTION i
    """,
    "documents": f"""
        SELECT {_uuid('doc.ZID')} AS id, doc.ZSUMMARY AS summary, doc.ZDOCUMENTDESCRIPTION AS description,
               (SELECT group_concat(p.ZNAME, ', ') FROM Z_4PROJECTS j
                  JOIN ZPROJECT p ON p.Z_PK = j.Z_13PROJECTS WHERE j.Z_4DOCUMENTS1 = doc.Z_PK) AS projects,
               (SELECT COUNT(*) FROM ZATTACHMENT a WHERE a.ZDOCUMENT = doc.Z_PK) AS attachment_count,
               datetime(doc.ZCREATEDAT + {APPLE_EPOCH_OFFSET}, 'unixepoch', 'localtime') AS created_at,
               doc.Z_PK AS pk
        FROM ZDOCUMENT doc
    """,
    "email_conversations": f"""
        SELECT {_uuid('c.ZID')} AS id, c.ZTHREADKEY AS thread_key,
               CASE WHEN c.ZDISMISSED = 1 THEN 'dismissed'
                    WHEN c.ZACCEPTED = 1 THEN 'accepted' ELSE 'unclassified' END AS triage_state,
               c.ZIMPORTANCERAW AS importance,
               (SELECT pe.ZNAME FROM ZPERSON pe WHERE pe.Z_PK = c.ZPERSON) AS other_party,
               (SELECT group_concat(p.ZNAME, ', ') FROM Z_5PROJECTS j
                  JOIN ZPROJECT p ON p.Z_PK = j.Z_13PROJECTS1 WHERE j.Z_5CONVERSATIONS = c.Z_PK) AS projects,
               (SELECT COUNT(*) FROM ZEMAILMESSAGE m WHERE m.ZCONVERSATION = c.Z_PK) AS message_count,
               (SELECT datetime(MAX(m.ZDATE) + {APPLE_EPOCH_OFFSET}, 'unixepoch', 'localtime')
                  FROM ZEMAILMESSAGE m WHERE m.ZCONVERSATION = c.Z_PK) AS latest_at,
               c.Z_PK AS pk
        FROM ZEMAILCONVERSATION c
    """,
    "emails": f"""
        SELECT {_uuid('m.ZID')} AS id, m.ZSUBJECT AS subject, m.ZDIRECTION AS direction,
               datetime(m.ZDATE + {APPLE_EPOCH_OFFSET}, 'unixepoch', 'localtime') AS date,
               m.ZFROMNAME AS from_name, m.ZFROMADDRESS AS from_address, m.ZSUMMARY AS summary,
               (SELECT pe.ZNAME FROM ZPERSON pe WHERE pe.Z_PK = m.ZPERSON) AS person,
               (SELECT c.ZTHREADKEY FROM ZEMAILCONVERSATION c WHERE c.Z_PK = m.ZCONVERSATION) AS conversation,
               m.Z_PK AS pk
        FROM ZEMAILMESSAGE m
    """,
    "diary_days": f"""
        SELECT {_uuid('d.ZID')} AS id, date(d.ZDATE + {APPLE_EPOCH_OFFSET}, 'unixepoch', 'localtime') AS day,
               (SELECT COUNT(*) FROM ZFOCUSBLOCK b WHERE b.ZDAYRECORD = d.Z_PK) AS focus_block_count,
               (SELECT COUNT(*) FROM ZNOTE n WHERE n.ZDAYRECORD = d.Z_PK) AS note_count,
               (SELECT COUNT(*) FROM ZTASK t WHERE t.ZDAYRECORD = d.Z_PK) AS task_count,
               d.Z_PK AS pk
        FROM ZDAYRECORD d
    """,
}

# Views searched by the `search` tool: view -> (label column, columns to match).
SEARCHABLE = {
    "tasks": ("summary", ["summary", "notes", "project", "assignee"]),
    "meetings": ("summary", ["summary", "projects", "attendees", "minutes_markdown"]),
    "projects": ("name", ["name", "stream", "description"]),
    "notes": ("title", ["title", "content", "project"]),
    "people": ("name", ["name", "institution", "emails_json"]),
    "email_conversations": ("thread_key", ["thread_key", "other_party", "projects"]),
}

MAX_ROWS = 2000
DEFAULT_ROWS = 200
MAX_CELL = 4000

SELECT_ONLY = re.compile(r"^\s*(select|with)\b", re.IGNORECASE)
FORBIDDEN = re.compile(
    r"\b(insert|update|delete|drop|alter|create|replace|attach|detach|pragma|vacuum|reindex|begin|commit)\b",
    re.IGNORECASE,
)


class Store:
    """A read-only connection with the friendly views installed as TEMP views."""

    def __init__(self, path: str):
        self.path = path
        self._conn: sqlite3.Connection | None = None

    def connect(self) -> sqlite3.Connection:
        if self._conn is None:
            if not os.path.exists(self.path):
                raise FileNotFoundError(f"store not found: {self.path}")
            # mode=ro: the app may hold this file; we never write to it.
            conn = sqlite3.connect(f"file:{self.path}?mode=ro", uri=True, check_same_thread=False)
            conn.row_factory = sqlite3.Row
            for name, body in VIEWS.items():
                conn.execute(f"CREATE TEMP VIEW {name} AS {body}")
            self._conn = conn
        return self._conn

    def query(self, sql: str, limit: int) -> tuple[list[str], list[list]]:
        if not SELECT_ONLY.match(sql):
            raise ValueError("only SELECT (or WITH … SELECT) statements are allowed")
        if ";" in sql.rstrip().rstrip(";"):
            raise ValueError("only one statement is allowed")
        if FORBIDDEN.search(sql):
            raise ValueError("this server is read-only; that statement is not allowed")
        cur = self.connect().execute(sql)
        rows = cur.fetchmany(limit)
        columns = [d[0] for d in cur.description] if cur.description else []
        return columns, [[_clip(r[c]) for c in columns] for r in rows]


def _clip(value):
    if isinstance(value, str) and len(value) > MAX_CELL:
        return value[:MAX_CELL] + f"… [{len(value) - MAX_CELL} more chars]"
    return value


def _rows_as_text(columns: list[str], rows: list[list], note: str | None = None) -> str:
    if not rows:
        return "No rows." + (f"\n\n{note}" if note else "")
    out = [json.dumps({"columns": columns, "row_count": len(rows), "rows": rows}, default=str)]
    if note:
        out.append(note)
    return "\n\n".join(out)


# ---------------------------------------------------------------------------- tools

def tool_schema(store: Store, _args: dict) -> str:
    conn = store.connect()
    lines = [
        "Readable views over the gbpDiary store (read-only). Query them with the `query` tool.",
        "Dates are local text 'YYYY-MM-DD HH:MM'. `pk` is the internal row id, useful for joins.",
        "",
        TIME_WARNING,
        "",
    ]
    for name in VIEWS:
        cols = [r[1] for r in conn.execute(f"PRAGMA table_info({name})")]
        count = conn.execute(f"SELECT COUNT(*) FROM {name}").fetchone()[0]
        lines.append(f"{name} ({count} rows): {', '.join(cols)}")
    return "\n".join(lines)


def tool_query(store: Store, args: dict) -> str:
    sql = (args.get("sql") or "").strip()
    if not sql:
        raise ValueError("`sql` is required")
    limit = min(int(args.get("limit") or DEFAULT_ROWS), MAX_ROWS)
    columns, rows = store.query(sql, limit)
    note = TIME_WARNING if re.search(r"hours", " ".join(columns), re.IGNORECASE) else None
    return _rows_as_text(columns, rows, note)


def tool_search(store: Store, args: dict) -> str:
    text = (args.get("text") or "").strip()
    if not text:
        raise ValueError("`text` is required")
    per_view = min(int(args.get("limit_per_kind") or 10), 100)
    like = f"%{text.lower()}%"
    results: list[str] = []
    conn = store.connect()
    for view, (label, columns) in SEARCHABLE.items():
        where = " OR ".join(f"lower(COALESCE({c}, '')) LIKE ?" for c in columns)
        sql = f"SELECT {label} AS label, * FROM {view} WHERE {where} LIMIT {per_view}"
        rows = conn.execute(sql, [like] * len(columns)).fetchall()
        if not rows:
            continue
        results.append(f"## {view} ({len(rows)})")
        for row in rows:
            data = {k: _clip(row[k]) for k in row.keys() if k not in ("label", "pk") and row[k] is not None}
            results.append(json.dumps(data, default=str))
    return "\n".join(results) if results else f"Nothing matched {text!r}."


def tool_counts(store: Store, _args: dict) -> str:
    conn = store.connect()
    counts = {name: conn.execute(f"SELECT COUNT(*) FROM {name}").fetchone()[0] for name in VIEWS}
    return json.dumps(counts, indent=2)



def tool_timesheet_report(_store: Store, args: dict) -> str:
    """The app's OWN time figures, exported from the Timesheet page — the only trustworthy source of
    hours here. Everything else in this server is raw records."""
    path = resolve_snapshot(args.get("path"))
    if path is None:
        return ("No timesheet export was found. In gbpDiary open the Timesheet page, choose the period you "
                "want, and use Export \u25b8 Report… (or Full content…) — that writes the authoritative "
                "figures this tool reads, and records where they went. Until then, hours cannot be answered "
                "correctly from this database.")
    with open(path) as handle:
        snap = json.load(handle)

    if snap.get("formatVersion") != 1:
        return f"Unsupported snapshot formatVersion {snap.get('formatVersion')!r}; this server expects 1."

    project = (args.get("project") or "").strip().lower()
    include_detail = bool(args.get("include_detail"))

    def walk(nodes, depth=0, out=None):
        out = [] if out is None else out
        for node in nodes:
            out.append((depth, node))
            walk(node.get("children") or [], depth + 1, out)
        return out

    period, totals = snap["period"], snap["totals"]
    # An export is a folder: data.json + summary.md + content/.
    tree = os.path.join(os.path.dirname(path), "content")
    if not os.path.isdir(tree):   # pre-folder exports wrote <base>_content beside <base>.json
        tree = os.path.splitext(path)[0] + "_content"
    lines = [
        f"Source: {path}",
    ] + ([f"Full content tree (read these markdown files directly): {tree}"]
         if os.path.isdir(tree) else []) + [
        f"Period: {period['label']}  ({period['start']} .. {period['end']} exclusive)",
        f"Exported: {snap['generatedAt']}  — these are the app's computed figures, not raw sums.",
        f"Total: {totals['hours']:.2f}h ({totals['days']:.2f}d); overtime {totals['overtimeHours']:.2f}h; "
        f"standard {totals['standardHours']:.2f}h",
    ]
    if totals.get("overLoggedHours", 0) > 0.05:
        lines.append(f"Over-logged by {totals['overLoggedHours']:.2f}h "
                     "(activity inside focus blocks exceeds their capacity), so project hours sum higher "
                     "than the total.")
    lines.append("")

    matched = 0
    for depth, node in walk(snap.get("projects") or []):
        if project and project not in node["name"].lower():
            continue
        matched += 1
        pad = "  " * depth
        suffix = ""
        if abs(node["subtreeHours"] - node["hours"]) > 0.001:
            suffix = f" (with subprojects {node['subtreeHours']:.2f}h)"
        lines.append(f"{pad}{node['name']} — {node['hours']:.2f}h, "
                     f"{node['distinctWeeks']} week(s){suffix}")
        if node.get("summary"):
            lines.append(f"{pad}  {node['summary']}")
        if include_detail:
            for row in node.get("rows") or []:
                hours = f" {row['hours']:.2f}h" if row["hours"] else ""
                lines.append(f"{pad}  • [{row['kind']}] {row['title']}{hours}")
                for detail in row.get("details") or []:
                    lines.append(f"{pad}    - {detail['text']} ({detail['hours']:.2f}h)")
            for note in node.get("notes") or []:
                lines.append(f"{pad}  • note: {note['title']}: {note['text'][:300]}")

    if project and matched == 0:
        names = ", ".join(n["name"] for _, n in walk(snap.get("projects") or []))
        lines.append(f"No project matching {project!r} in this period. Present: {names}")

    content = snap.get("content")
    if args.get("include_content"):
        if not content:
            lines.append("")
            lines.append("No full content in this snapshot — it was exported as Export ▸ Report…. "
                         "Re-export with Export ▸ Full content… to include meeting minutes, note "
                         "markdown and the email correspondence.")
        else:
            lines.append("")
            lines.append(content.get("notice", ""))
            for meeting in content.get("meetings") or []:
                if project and project not in " ".join(meeting.get("projects") or []).lower():
                    continue
                lines.append("")
                lines.append(f"### Meeting: {meeting.get('summary') or '(no summary)'} "
                             f"({meeting['meetingAt']}) — {', '.join(meeting.get('projects') or []) or 'no project'}")
                if meeting.get("attendees"):
                    lines.append(f"Attendees: {', '.join(meeting['attendees'])}")
                if meeting.get("minutesMarkdown"):
                    lines.append(meeting["minutesMarkdown"])
            for note in content.get("notes") or []:
                if project and project != (note.get("project") or "").lower():
                    continue
                lines.append("")
                lines.append(f"### Note: {note.get('title') or '(untitled)'} "
                             f"({note['updatedAt']}) — {note.get('project') or 'no project'}")
                lines.append(note.get("markdown", ""))
            for convo in content.get("conversations") or []:
                if project and project not in " ".join(convo.get("projects") or []).lower():
                    continue
                lines.append("")
                lines.append(f"### Email thread: {convo.get('subject')} — "
                             f"{', '.join(convo.get('projects') or []) or 'no project'}"
                             f" (importance {convo.get('importance')}, "
                             f"{convo.get('loggedHours', 0):.2f}h logged)")
                for message in convo.get("messages") or []:
                    lines.append(f"- {message['direction']} {message['date']} from {message['from']}: "
                                 f"{message.get('summary') or message.get('subject')}")
    elif content:
        lines.append("")
        lines.append("This snapshot also carries full content (meeting minutes, note markdown, email "
                     "correspondence). Call again with include_content=true to read it.")
    return "\n".join(lines)


TOOLS = [
    {
        "name": "timesheet_report",
        "description": (
            "The app's OWN computed time figures for the period last exported from the Timesheet page "
            "(per project, nested, with the generated prose). USE THIS for any question about time spent — "
            "the `query` tool's hours are raw records and will disagree."
        ),
        "handler": tool_timesheet_report,
        "inputSchema": {
            "type": "object",
            "properties": {
                "project": {"type": "string", "description": "Only projects whose name contains this."},
                "include_detail": {"type": "boolean",
                                   "description": "Include the rows and notes that account for the hours."},
                "path": {"type": "string",
                         "description": ("A specific exported timesheet JSON to read. Defaults to the "
                                         "app's most recent export.")},
                "include_content": {"type": "boolean",
                                    "description": ("Include the full text behind the period — complete "
                                                    "meeting minutes, note markdown and email "
                                                    "correspondence (subjects + on-device summaries; "
                                                    "bodies are never stored). Requires a snapshot "
                                                    "exported with Export > Full content.")},
            },
        },
    },
    {
        "name": "schema",
        "description": "List the readable views available, their columns and row counts. Call this first.",
        "handler": tool_schema,
        "inputSchema": {"type": "object", "properties": {}},
    },
    {
        "name": "query",
        "description": (
            "Run one read-only SELECT against the readable views (see `schema`). "
            "Returns JSON {columns, row_count, rows}. " + TIME_WARNING
        ),
        "handler": tool_query,
        "inputSchema": {
            "type": "object",
            "properties": {
                "sql": {"type": "string", "description": "A single SELECT or WITH … SELECT statement."},
                "limit": {"type": "integer", "description": f"Max rows (default {DEFAULT_ROWS}, max {MAX_ROWS})."},
            },
            "required": ["sql"],
        },
    },
    {
        "name": "search",
        "description": "Free-text search across tasks, meetings, projects, notes, people and email conversations.",
        "handler": tool_search,
        "inputSchema": {
            "type": "object",
            "properties": {
                "text": {"type": "string"},
                "limit_per_kind": {"type": "integer", "description": "Max matches per kind (default 10)."},
            },
            "required": ["text"],
        },
    },
    {
        "name": "counts",
        "description": "Row counts for every view — a cheap way to orient before querying.",
        "handler": tool_counts,
        "inputSchema": {"type": "object", "properties": {}},
    },
]

INSTRUCTIONS = (
    "Read-only access to the gbpDiary database (tasks, meetings, projects, people, notes, diary days, "
    "email metadata). Start with `schema`, then use `query` with the readable view names. "
    + TIME_WARNING
    + " Email bodies are never stored, only subjects and on-device summaries."
)


def _result(id_, result):
    return {"jsonrpc": "2.0", "id": id_, "result": result}


def _error(id_, code, message):
    return {"jsonrpc": "2.0", "id": id_, "error": {"code": code, "message": message}}


def handle(message: dict, store: Store) -> dict | None:
    method = message.get("method")
    id_ = message.get("id")
    params = message.get("params") or {}

    if method == "initialize":
        return _result(id_, {
            "protocolVersion": params.get("protocolVersion", "2024-11-05"),
            "capabilities": {"tools": {}},
            "serverInfo": {"name": "gbpdiary", "version": "0.1.0"},
            "instructions": INSTRUCTIONS,
        })
    if method in ("notifications/initialized", "notifications/cancelled"):
        return None
    if method == "ping":
        return _result(id_, {})
    if method == "tools/list":
        return _result(id_, {"tools": [
            {k: t[k] for k in ("name", "description", "inputSchema")} for t in TOOLS
        ]})
    if method == "tools/call":
        name = params.get("name")
        args = params.get("arguments") or {}
        tool = next((t for t in TOOLS if t["name"] == name), None)
        if tool is None:
            return _result(id_, {"content": [{"type": "text", "text": f"Unknown tool {name!r}"}],
                                 "isError": True})
        try:
            text = tool["handler"](store, args)
            return _result(id_, {"content": [{"type": "text", "text": text}]})
        except Exception as exc:  # surfaced to the model, which can correct its SQL
            return _result(id_, {"content": [{"type": "text", "text": f"{type(exc).__name__}: {exc}"}],
                                 "isError": True})
    if id_ is None:
        return None
    return _error(id_, -32601, f"Method not found: {method}")


def main() -> int:
    store = Store(os.environ.get("GBPDIARY_STORE", DEFAULT_STORE))
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            message = json.loads(line)
        except json.JSONDecodeError:
            continue
        response = handle(message, store)
        if response is not None:
            sys.stdout.write(json.dumps(response) + "\n")
            sys.stdout.flush()
    return 0


if __name__ == "__main__":
    sys.exit(main())
