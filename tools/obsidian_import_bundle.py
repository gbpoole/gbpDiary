#!/usr/bin/env python3
"""Build a dry-run import bundle from an Obsidian vault.

This tool is intentionally read-only. It scans markdown files, applies the
Obsidian/Dataview conventions used by the old vault automation scripts, and
emits a JSON bundle that can be inspected before any SwiftData import is added.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
import uuid
from dataclasses import dataclass
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any


STRUCTURAL_TAGS = {
    "project",
    "person",
    "institution",
    "meeting",
    "minutes",
    "document",
}

SKIP_DIRS = {
    ".git",
    ".obsidian",
    ".trash",
    "node_modules",
}

GENERATED_CODE_LANGS = {
    "dataviewjs",
    "dataview",
    "meta-bind-button",
}

TASK_RE = re.compile(r"^(?P<indent>\s*)[-*]\s+\[(?P<mark>.)\]\s+(?P<text>.*)$")
INLINE_WIKILINK_FIELD_RE = re.compile(
    r"[\[(]\s*(?P<key>[A-Za-z][A-Za-z0-9_-]*)::\s*(?P<value>\[\[[^\]]+\]\])\s*[\])]"
)
INLINE_FIELD_RE = re.compile(r"[\[(]\s*(?P<key>[A-Za-z][A-Za-z0-9_-]*)::\s*(?P<value>[^\])]+)\s*[\])]?")
WIKILINK_RE = re.compile(r"\[\[(?P<link>[^\]]+)\]\]")
SECTION_RE = re.compile(r"^(?P<level>#{1,6})\s+(?P<title>.+?)\s*$")
WEEKDAY_HEADING_RE = re.compile(r"^(?P<weekday>Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday)\s*\((?P<day>\d{1,2})(?:st|nd|rd|th)?\)", re.IGNORECASE)
DATE_IN_FILENAME_RE = re.compile(r"(?P<date>\d{4}-\d{2}-\d{2})(?:[_-](?P<hour>\d{2})[.:-](?P<minute>\d{2}))?")
COMPLETION_STAMP_RE = re.compile(r"\s*✅\s*(?P<date>\d{4}-\d{2}-\d{2})\s*")
CANCELLED_STAMP_RE = re.compile(r"\s*🚫\s*(?P<date>\d{4}-\d{2}-\d{2})\s*")
SCHEDULED_STAMP_RE = re.compile(r"\s*[⏳📅]\s*(?P<date>\d{4}-\d{2}-\d{2})\s*")
TAG_RE = re.compile(r"(^|\s)#(?P<tag>[A-Za-z0-9_/-]+)(?=\s|$)")
OBSIDIAN_IMAGE_RE = re.compile(r"!\[\[(?P<target>[^\]]+)\]\]")
MARKDOWN_IMAGE_RE = re.compile(r"!\[[^\]]*\]\((?P<target>[^)]+)\)")
IMAGE_EXTENSIONS = {".png", ".jpg", ".jpeg", ".gif", ".heic", ".tif", ".tiff", ".webp"}


def stable_uuid(kind: str, key: str) -> str:
    return str(uuid.uuid5(uuid.NAMESPACE_URL, f"gbpDiary.obsidian-import:{kind}:{key}"))


def sha1_text(text: str) -> str:
    return hashlib.sha1(text.encode("utf-8")).hexdigest()


def clean_scalar(value: Any) -> str:
    if value is None:
        return ""
    if isinstance(value, list):
        return clean_scalar(value[0]) if value else ""
    text = str(value).replace("\u00a0", " ").strip()
    if len(text) >= 2 and text[0] == text[-1] and text[0] in {'"', "'"}:
        text = text[1:-1]
    return text.strip()


def as_list(value: Any) -> list[str]:
    if value is None:
        return []
    if isinstance(value, list):
        items = value
    else:
        text = clean_scalar(value)
        if text.startswith("[") and text.endswith("]"):
            items = [p.strip() for p in text[1:-1].split(",")]
        elif "," in text and "[[" not in text:
            items = [p.strip() for p in text.split(",")]
        else:
            items = [text]
    return [clean_scalar(item) for item in items if clean_scalar(item) not in {"", '""'}]


def first_field(frontmatter: dict[str, Any], *names: str) -> Any:
    lower = {key.lower(): key for key in frontmatter.keys()}
    for name in names:
        key = lower.get(name.lower())
        if key is not None:
            return frontmatter.get(key)
    return None


def normalize_type(frontmatter: dict[str, Any]) -> str | None:
    values = [v.lower() for v in as_list(first_field(frontmatter, "type", "tags"))]
    for value in values:
        if value in STRUCTURAL_TAGS:
            return "minutes" if value == "meeting" else value
    return None


def canonical_markdown_path(raw: str, current_folder: str | None = None) -> str | None:
    text = clean_scalar(raw)
    if not text:
        return None
    match = WIKILINK_RE.search(text)
    if match:
        text = match.group("link")
    elif text.startswith("[") and text.endswith("]") and "|" in text:
        text = text[1:-1]
    text = text.split("|")[0].split("#")[0].split("^")[0].strip()
    if not text:
        return None
    if not Path(text).suffix:
        text += ".md"
    if current_folder and "/" not in text:
        text = f"{current_folder.rstrip('/')}/{text}"
    return text.replace("\\", "/")


def display_name_from_link(raw: str) -> str:
    text = clean_scalar(raw)
    match = WIKILINK_RE.search(text)
    if match:
        inner = match.group("link")
        if "|" in inner:
            return inner.split("|", 1)[1].strip()
        text = inner
    text = text.split("#")[0].split("^")[0].strip()
    return Path(text).stem if text else ""


def wikilinks_to_display_text(text: str) -> str:
    def replace(match: re.Match[str]) -> str:
        return display_name_from_link(match.group(0))

    return WIKILINK_RE.sub(replace, text)


def parse_date(raw: Any, fallback_path: str | None = None) -> str | None:
    text = clean_scalar(raw)
    candidates = [text]
    if fallback_path:
        candidates.append(Path(fallback_path).stem)
    for candidate in candidates:
        if not candidate:
            continue
        candidate = candidate.replace("T", " ").replace("_", " ")
        for fmt in ("%Y-%m-%d %H.%M", "%Y-%m-%d %H:%M", "%Y-%m-%d %H-%M", "%Y-%m-%d"):
            try:
                dt = datetime.strptime(candidate[:16] if "%H" in fmt else candidate[:10], fmt)
                return dt.isoformat(timespec="minutes")
            except ValueError:
                pass
        match = DATE_IN_FILENAME_RE.search(candidate)
        if match:
            hour = int(match.group("hour") or 0)
            minute = int(match.group("minute") or 0)
            dt = datetime.strptime(match.group("date"), "%Y-%m-%d").replace(hour=hour, minute=minute)
            return dt.isoformat(timespec="minutes")
    return None


def parse_duration(raw: Any) -> dict[str, Any] | None:
    text = clean_scalar(raw).lower()
    match = re.fullmatch(r"(?P<value>\d+(?:\.\d+)?)\s*(?P<unit>[hdw])", text)
    if not match:
        return None
    value = float(match.group("value"))
    unit = match.group("unit")
    hours = value * {"h": 1.0, "d": 7.6, "w": 38.0}[unit]
    return {"value": value, "unit": unit, "hoursNormalized": hours}


def parse_date_only(raw: Any) -> str | None:
    parsed = parse_date(raw)
    return parsed[:10] if parsed else None


def diary_section_date(title: str, week_start: str | None) -> str | None:
    if not week_start:
        return None
    match = WEEKDAY_HEADING_RE.match(title.strip())
    if not match:
        return None
    try:
        start = datetime.strptime(week_start[:10], "%Y-%m-%d")
    except ValueError:
        return None
    weekdays = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
    offset = weekdays.index(match.group("weekday").lower())
    date = start + timedelta(days=offset)
    return date.date().isoformat()


def parse_followed_up(raw: Any) -> list[str]:
    text = clean_scalar(raw)
    if not text:
        return []
    text = text.strip("[]")
    values = re.split(r"[;,]", text)
    dates: list[str] = []
    for value in values:
        parsed = parse_date_only(value.strip())
        if parsed and parsed not in dates:
            dates.append(parsed)
    return sorted(dates)


def normalize_tag(raw: str) -> str:
    return re.sub(r"_+", "_", re.sub(r"\s+", "_", raw.strip().lstrip("#"))).strip("_")


def merge_tags(*groups: list[str]) -> list[str]:
    tags = {normalize_tag(tag) for group in groups for tag in group}
    return sorted(tag for tag in tags if tag and tag.lower() not in STRUCTURAL_TAGS)


def frontmatter_tags(frontmatter: dict[str, Any]) -> list[str]:
    return merge_tags(
        as_list(first_field(frontmatter, "tags")),
        as_list(first_field(frontmatter, "type")),
    )


def markdown_tags(markdown: str) -> list[str]:
    return merge_tags([match.group("tag") for match in TAG_RE.finditer(markdown)])


def image_target(raw: str) -> str:
    text = clean_scalar(raw)
    text = text.split("|", 1)[0].split("#", 1)[0].split("^", 1)[0].strip()
    return text.replace("\\", "/")


def is_image_ref(ref: str) -> bool:
    return Path(image_target(ref)).suffix.lower() in IMAGE_EXTENSIONS


def resolve_note_image(ref: str, source: SourceFile, vault: Path) -> Path | None:
    target = image_target(ref)
    if not target or not is_image_ref(target):
        return None
    raw = Path(target)
    candidates: list[Path] = []
    if raw.is_absolute():
        candidates.append(raw)
    candidates.extend([
        source.path.parent / target,
        source.path.with_suffix("") / target,
        vault / target,
    ])
    return next((candidate for candidate in candidates if candidate.exists()), None)


def note_markdown_and_attachments(source: SourceFile, markdown: str, vault: Path, diagnostics: list[dict[str, Any]]) -> tuple[str, list[dict[str, Any]]]:
    """Rewrite Obsidian/markdown image links into managed `attachment://<uuid>` refs and collect
    the referenced attachments. Notes are plain markdown in the app; images are resolved by id."""
    attachments: list[dict[str, Any]] = []
    parts: list[str] = []
    cursor = 0
    matches = sorted(
        list(OBSIDIAN_IMAGE_RE.finditer(markdown)) + list(MARKDOWN_IMAGE_RE.finditer(markdown)),
        key=lambda match: match.start(),
    )

    for match in matches:
        parts.append(markdown[cursor:match.start()])
        target = image_target(match.group("target"))
        resolved = resolve_note_image(target, source, vault)
        if resolved:
            ref = resolved.relative_to(vault).as_posix() if resolved.is_relative_to(vault) else resolved.as_posix()
            attachment_id = stable_uuid("noteAttachment", f"{source.rel_path}:{target}")
            attachments.append({"id": attachment_id, "ref": ref, "fileName": resolved.name, "kind": "image", "displayName": resolved.stem})
            parts.append(f"![{resolved.stem}](attachment://{attachment_id})")
        else:
            diagnostics.append({"severity": "warning", "code": "unresolved-image", "source": source.rel_path, "value": target})
            parts.append(match.group(0))
        cursor = match.end()
    parts.append(markdown[cursor:])
    return ("".join(parts), attachments)


def parse_frontmatter(text: str) -> tuple[dict[str, Any], str]:
    if not text.startswith("---\n"):
        return {}, text
    end = text.find("\n---", 4)
    if end == -1:
        return {}, text
    body = text[4:end]
    rest = text[end + len("\n---") :].lstrip("\n")
    result: dict[str, Any] = {}
    current_key: str | None = None
    for raw_line in body.splitlines():
        line = raw_line.rstrip()
        item_match = re.match(r"^\s*-\s*(.*)$", line)
        if item_match and current_key:
            result.setdefault(current_key, [])
            if not isinstance(result[current_key], list):
                result[current_key] = [result[current_key]]
            result[current_key].append(item_match.group(1).strip())
            continue
        key_match = re.match(r"^([^:#][^:]*):\s*(.*)$", line)
        if key_match:
            current_key = key_match.group(1).strip()
            value = key_match.group(2).strip()
            result[current_key] = [] if value == "" else value
        elif current_key and line.strip():
            previous = result.get(current_key, "")
            result[current_key] = f"{previous}\n{line}" if previous else line
    return result, rest


@dataclass
class SourceFile:
    path: Path
    rel_path: str
    frontmatter: dict[str, Any]
    body: str
    inferred_type: str | None


def iter_markdown(vault: Path) -> list[Path]:
    files: list[Path] = []
    for path in vault.rglob("*.md"):
        if any(part in SKIP_DIRS for part in path.relative_to(vault).parts):
            continue
        files.append(path)
    return sorted(files)


def infer_type(rel_path: str, frontmatter: dict[str, Any]) -> str | None:
    explicit = normalize_type(frontmatter)
    if explicit:
        return explicit
    lower = rel_path.lower()
    if "/people/" in f"/{lower}":
        return "person"
    if "/institutions/" in f"/{lower}":
        return "institution"
    if "/projects/" in f"/{lower}" or "/project/" in f"/{lower}":
        return "project"
    if "/minutes/" in f"/{lower}" or "/meetings/" in f"/{lower}":
        return "minutes"
    if "/documents/" in f"/{lower}" or "/document/" in f"/{lower}":
        return "document"
    if lower.startswith("diary/") or DATE_IN_FILENAME_RE.search(Path(rel_path).stem):
        return "diary"
    return None


def load_sources(vault: Path) -> list[SourceFile]:
    sources: list[SourceFile] = []
    for path in iter_markdown(vault):
        text = path.read_text(encoding="utf-8", errors="replace")
        frontmatter, body = parse_frontmatter(text)
        rel_path = path.relative_to(vault).as_posix()
        sources.append(SourceFile(path, rel_path, frontmatter, body, infer_type(rel_path, frontmatter)))
    return sources


def strip_generated_blocks(markdown: str) -> str:
    lines = markdown.splitlines()
    output: list[str] = []
    in_code = False
    skip_code = False
    for line in lines:
        fence = re.match(r"^```\s*([^`]*)\s*$", line)
        if fence:
            if not in_code:
                in_code = True
                lang = fence.group(1).strip().lower()
                skip_code = lang in GENERATED_CODE_LANGS
                if not skip_code:
                    output.append(line)
            else:
                if not skip_code:
                    output.append(line)
                in_code = False
                skip_code = False
            continue
        if not skip_code:
            output.append(line)
    return "\n".join(output).strip()


def sections(markdown: str) -> dict[str, str]:
    lines = markdown.splitlines()
    result: dict[str, list[str]] = {}
    current = ""
    for line in lines:
        match = SECTION_RE.match(line)
        if match:
            current = match.group("title").strip().lower()
            result.setdefault(current, [])
        else:
            result.setdefault(current, []).append(line)
    return {key: "\n".join(value).strip() for key, value in result.items()}


def extract_inline_fields(text: str) -> tuple[dict[str, str], str]:
    fields: dict[str, str] = {}

    def replace(match: re.Match[str]) -> str:
        fields[match.group("key").lower()] = match.group("value").strip()
        return ""

    cleaned = INLINE_WIKILINK_FIELD_RE.sub(replace, text)
    cleaned = INLINE_FIELD_RE.sub(replace, cleaned)
    return fields, re.sub(r"\s+", " ", cleaned).strip()


def extract_task_metadata(raw_text: str, checkbox_mark: str, source_date: str | None) -> dict[str, Any]:
    inline_fields, summary = extract_inline_fields(raw_text)
    completion_match = COMPLETION_STAMP_RE.search(summary)
    cancelled_match = CANCELLED_STAMP_RE.search(summary)
    scheduled_match = SCHEDULED_STAMP_RE.search(summary)
    tags = [normalize_tag(match.group("tag")) for match in TAG_RE.finditer(summary)]
    tags = sorted({tag for tag in tags if tag})

    summary = COMPLETION_STAMP_RE.sub(" ", summary)
    summary = CANCELLED_STAMP_RE.sub(" ", summary)
    summary = SCHEDULED_STAMP_RE.sub(" ", summary)
    summary = TAG_RE.sub(lambda match: match.group(1), summary)
    summary = wikilinks_to_display_text(summary)
    summary = re.sub(r"\s+", " ", summary).strip()
    if not summary:
        summary = "Untitled task"

    mark = checkbox_mark.strip().lower()
    status = "todo"
    if mark == "x":
        status = "completed"
    elif mark == "?":
        status = "followUpPending"
    elif mark == "-":
        status = "cancelled"

    completed_at = completion_match.group("date") if completion_match else None
    cancelled_at = cancelled_match.group("date") if cancelled_match else None
    scheduled_at = scheduled_match.group("date") if scheduled_match else None
    follow_up_at = parse_date_only(inline_fields.get("follow_up"))

    if status == "completed" and completed_at is None:
        completed_at = source_date
    if status == "cancelled" and cancelled_at is None:
        cancelled_at = source_date

    return {
        "inlineFields": inline_fields,
        "summary": summary,
        "status": status,
        "tags": tags,
        "duration": parse_duration(inline_fields.get("duration")),
        "scheduledAt": scheduled_at,
        "completedAt": completed_at,
        "cancelledAt": cancelled_at,
        "followUpAt": follow_up_at,
        "followedUpHistory": parse_followed_up(inline_fields.get("followed_up")),
    }


def extract_tasks(source: SourceFile) -> list[dict[str, Any]]:
    tasks: list[dict[str, Any]] = []
    heading_stack: list[tuple[int, str]] = []
    occurrence_by_hash: dict[str, int] = {}
    source_date = parse_date_only(first_field(source.frontmatter, "date", "created")) or parse_date_only(source.rel_path)
    week_start = parse_date_only(first_field(source.frontmatter, "week-start"))
    current_section_date: str | None = source_date
    for line_number, line in enumerate(source.body.splitlines(), start=1):
        section_match = SECTION_RE.match(line)
        if section_match:
            level = len(section_match.group("level"))
            heading_stack = [h for h in heading_stack if h[0] < level]
            heading_stack.append((level, section_match.group("title").strip()))
            current_section_date = diary_section_date(section_match.group("title"), week_start) or source_date
            continue
        task_match = TASK_RE.match(line)
        if not task_match:
            continue
        raw_text = task_match.group("text").strip()
        if not raw_text:
            continue
        metadata = extract_task_metadata(raw_text, task_match.group("mark"), current_section_date)
        summary = metadata["summary"]
        section_path = " / ".join(title for _, title in heading_stack)
        normalized_hash = sha1_text(f"{source.rel_path}\n{section_path}\n{summary.lower()}")
        occurrence = occurrence_by_hash.get(normalized_hash, 0)
        occurrence_by_hash[normalized_hash] = occurrence + 1
        task = {
                "id": stable_uuid("task", f"{source.rel_path}:{line_number}:{normalized_hash}:{occurrence}"),
                "summary": summary,
                "rawText": raw_text,
                "notes": "",
                "indent": len(task_match.group("indent").replace("\t", "    ")),
                "line": line_number,
                "section": section_path,
                "sourcePath": source.rel_path,
                "sourceType": source.inferred_type,
                "sectionDate": current_section_date,
            }
        task.update(metadata)
        tasks.append(task)
    return tasks


def source_context(source: SourceFile, section: str | None = None) -> dict[str, Any]:
    return {
        "externalSourceId": source.rel_path,
        "sourceRecordId": source.rel_path,
        "sourceSection": section,
        "sourceLineFingerprint": sha1_text(source.rel_path),
    }


def build_bundle(vault: Path) -> dict[str, Any]:
    sources = load_sources(vault)
    by_path = {source.rel_path: source for source in sources}
    diagnostics: list[dict[str, Any]] = []

    institutions: list[dict[str, Any]] = []
    people: list[dict[str, Any]] = []
    projects: list[dict[str, Any]] = []
    minutes: list[dict[str, Any]] = []
    documents: list[dict[str, Any]] = []
    notes: list[dict[str, Any]] = []
    day_records: list[dict[str, Any]] = []
    day_record_ids: set[str] = set()
    focus_blocks: list[dict[str, Any]] = []
    tasks: list[dict[str, Any]] = []

    def link_key(value: str) -> str:
        return value.replace("\u00a0", " ").lower() if "/" not in value else value.replace("\u00a0", " ")

    link_index: dict[str, dict[str, str]] = {}
    for source in sources:
        identity = stable_uuid(source.inferred_type or "source", source.rel_path)
        link_index[link_key(source.rel_path)] = {"id": identity, "type": source.inferred_type or "unknown"}
        link_index[Path(source.rel_path).stem.replace("\u00a0", " ").lower()] = {"id": identity, "type": source.inferred_type or "unknown"}

    def ref_id(raw: Any, expected_type: str, source: SourceFile) -> str | None:
        path = canonical_markdown_path(clean_scalar(raw))
        candidates = []
        if path:
            candidates.append(path)
            candidates.append(path.replace("CMS/", ""))
            candidates.append(Path(path).stem.lower())
        for candidate in candidates:
            found = link_index.get(link_key(candidate))
            if found and found["type"] in {expected_type, "unknown"}:
                return found["id"]
        label = display_name_from_link(clean_scalar(raw))
        if label:
            diagnostics.append({"severity": "warning", "code": "unresolved-link", "source": source.rel_path, "expectedType": expected_type, "value": clean_scalar(raw)})
        return None

    for source in sources:
        fm = source.frontmatter
        kind = source.inferred_type
        created = parse_date(first_field(fm, "created", "createdAt"), source.rel_path)
        updated = parse_date(first_field(fm, "updated", "updatedAt"), source.rel_path) or created
        basename = Path(source.rel_path).stem
        type_tags = frontmatter_tags(fm)

        if kind == "institution":
            institutions.append({
                "id": stable_uuid("institution", source.rel_path),
                "name": basename,
                "createdAt": created,
                "updatedAt": updated,
                "sourceContext": source_context(source),
            })
        elif kind == "person":
            people.append({
                "id": stable_uuid("person", source.rel_path),
                "name": basename,
                "email": clean_scalar(first_field(fm, "email")) or None,
                "institutionId": ref_id(first_field(fm, "institution"), "institution", source),
                "tags": type_tags,
                "createdAt": created,
                "updatedAt": updated,
                "sourceContext": source_context(source),
            })
        elif kind == "project":
            projects.append({
                "id": stable_uuid("project", source.rel_path),
                "name": basename,
                "description": clean_scalar(first_field(fm, "description")) or None,
                "stream": clean_scalar(first_field(fm, "projectType", "stream")) or None,
                "isCompleted": clean_scalar(first_field(fm, "completed", "isCompleted")).lower() == "true",
                "parentProjectIds": [rid for rid in (ref_id(v, "project", source) for v in as_list(first_field(fm, "parent"))) if rid],
                "devTeamPersonIds": [rid for rid in (ref_id(v, "person", source) for v in as_list(first_field(fm, "devTeam"))) if rid],
                "sciTeamPersonIds": [rid for rid in (ref_id(v, "person", source) for v in as_list(first_field(fm, "sciTeam"))) if rid],
                "institutionIds": [rid for rid in (ref_id(v, "institution", source) for v in as_list(first_field(fm, "institution", "institutions"))) if rid],
                "tags": type_tags,
                "createdAt": created,
                "updatedAt": updated,
                "sourceContext": source_context(source),
            })
        elif kind == "minutes":
            source_sections = sections(strip_generated_blocks(source.body))
            note_text = source_sections.get("notes", "").strip()
            note_tags = merge_tags(type_tags, markdown_tags(note_text))
            note_content, note_attachments = note_markdown_and_attachments(source, note_text, vault, diagnostics)
            note_id = stable_uuid("note", f"{source.rel_path}:minutes-note")
            notes.append({
                "id": note_id,
                "content": note_content,
                "attachments": note_attachments,
                "tags": note_tags,
                "sourcePath": source.rel_path,
                "createdAt": created,
                "updatedAt": updated,
                "sourceContext": source_context(source, "Notes"),
            })
            minutes.append({
                "id": stable_uuid("minutes", source.rel_path),
                "summary": clean_scalar(first_field(fm, "summary")) or basename,
                "meetingAt": parse_date(first_field(fm, "date", "meetingAt"), source.rel_path),
                "duration": parse_duration(first_field(fm, "duration")),
                "projectIds": [rid for rid in (ref_id(v, "project", source) for v in as_list(first_field(fm, "project", "projects"))) if rid],
                "attendeePersonIds": [rid for rid in (ref_id(v, "person", source) for v in as_list(first_field(fm, "attendees"))) if rid],
                "noteId": note_id,
                "createdAt": created,
                "updatedAt": updated,
                "sourceContext": source_context(source),
            })
        elif kind == "document":
            source_sections = sections(strip_generated_blocks(source.body))
            contents_links = [m.group("link") for m in WIKILINK_RE.finditer(source_sections.get("contents", ""))]
            attachments = as_list(first_field(fm, "attachment", "attachments")) + contents_links
            documents.append({
                "id": stable_uuid("document", source.rel_path),
                "summary": basename,
                "description": clean_scalar(first_field(fm, "description")) or source_sections.get("notes") or None,
                "projectIds": [rid for rid in (ref_id(v, "project", source) for v in as_list(first_field(fm, "project", "projects"))) if rid],
                "attachmentRefs": sorted(set(filter(None, (canonical_markdown_path(a) or clean_scalar(a) for a in attachments)))),
                "createdAt": created,
                "updatedAt": updated,
                "sourceContext": source_context(source),
            })
        elif kind == "diary":
            date = parse_date(first_field(fm, "date"), source.rel_path)
            if date:
                day_id = stable_uuid("dayRecord", date[:10])
                note_text = strip_generated_blocks(source.body)
                note_tags = merge_tags(type_tags, markdown_tags(note_text))
                if day_id not in day_record_ids:
                    day_records.append({
                        "id": day_id,
                        "date": date[:10],
                        "tags": note_tags,
                        "createdAt": created,
                        "updatedAt": updated,
                        "sourceContext": source_context(source),
                    })
                    day_record_ids.add(day_id)
                if note_text.strip():
                    note_content, note_attachments = note_markdown_and_attachments(source, note_text, vault, diagnostics)
                    notes.append({
                        "id": stable_uuid("note", f"{source.rel_path}:day-note"),
                        "content": note_content,
                        "attachments": note_attachments,
                        "tags": note_tags,
                        "dayRecordId": day_id,
                        "sourcePath": source.rel_path,
                        "createdAt": created,
                        "updatedAt": updated,
                        "sourceContext": source_context(source),
                    })

        for task in extract_tasks(source):
            fields = task["inlineFields"]
            task["projectId"] = ref_id(fields.get("project") or first_field(fm, "project"), "project", source)
            task["assigneePersonId"] = ref_id(fields.get("who") or fields.get("assignee"), "person", source)
            task["minutesId"] = ref_id(fields.get("minutes"), "minutes", source)
            task["originMinutesId"] = task["minutesId"] or (stable_uuid("minutes", source.rel_path) if kind == "minutes" else None)
            diary_date = task.get("sectionDate") if kind == "diary" else None
            task["dayRecordId"] = stable_uuid("dayRecord", diary_date[:10]) if diary_date else None
            if kind == "diary" and diary_date and task["dayRecordId"] not in day_record_ids:
                day_records.append({
                    "id": task["dayRecordId"],
                    "date": diary_date[:10],
                    "tags": merge_tags(type_tags, task.get("tags") or []),
                    "createdAt": created,
                    "updatedAt": updated,
                    "sourceContext": source_context(source, task.get("section")),
                })
                day_record_ids.add(task["dayRecordId"])
            task["sourceContext"] = source_context(source, task.get("section"))

            if kind == "diary" and task.get("indent", 0) == 0 and task.get("dayRecordId"):
                focus_blocks.append({
                    "id": stable_uuid("focusBlock", f"{source.rel_path}:{task['line']}:{task['summary'].lower()}"),
                    "summary": task["summary"],
                    "rawText": task.get("rawText"),
                    "duration": task.get("duration") or {"value": 1.0, "unit": "d", "hoursNormalized": 7.6},
                    "slot": "allDay",
                    "sortOrder": task.get("line") or 0,
                    "taskId": stable_uuid("focusBlockTask", f"{source.rel_path}:{task['line']}:{task['summary'].lower()}"),
                    "projectId": task.get("projectId"),
                    "assigneePersonId": task.get("assigneePersonId"),
                    "dayRecordId": task.get("dayRecordId"),
                    "tags": task.get("tags") or [],
                    "sourceContext": task.get("sourceContext"),
                })
                continue

            tasks.append(task)

    task_status_counts: dict[str, int] = {}
    task_metadata_counts = {
        "withAssignee": 0,
        "withProject": 0,
        "withMinutes": 0,
        "withDuration": 0,
        "withScheduledAt": 0,
        "withFollowUpAt": 0,
        "withTags": 0,
    }
    for task in tasks:
        status = task.get("status") or "unknown"
        task_status_counts[status] = task_status_counts.get(status, 0) + 1
        if task.get("assigneePersonId"):
            task_metadata_counts["withAssignee"] += 1
        if task.get("projectId"):
            task_metadata_counts["withProject"] += 1
        if task.get("minutesId") or task.get("originMinutesId"):
            task_metadata_counts["withMinutes"] += 1
        if task.get("duration"):
            task_metadata_counts["withDuration"] += 1
        if task.get("scheduledAt"):
            task_metadata_counts["withScheduledAt"] += 1
        if task.get("followUpAt"):
            task_metadata_counts["withFollowUpAt"] += 1
        if task.get("tags"):
            task_metadata_counts["withTags"] += 1

    return {
        "schemaVersion": 1,
        "generatedAt": datetime.now().isoformat(timespec="seconds"),
        "vaultPath": str(vault),
        "counts": {
            "sources": len(sources),
            "institutions": len(institutions),
            "people": len(people),
            "projects": len(projects),
            "minutes": len(minutes),
            "documents": len(documents),
            "notes": len(notes),
            "dayRecords": len(day_records),
            "focusBlocks": len(focus_blocks),
            "tasks": len(tasks),
            "diagnostics": len(diagnostics),
        },
        "summary": {
            "taskStatusCounts": dict(sorted(task_status_counts.items())),
            "taskMetadataCounts": task_metadata_counts,
        },
        "institutions": institutions,
        "people": people,
        "projects": projects,
        "minutes": minutes,
        "documents": documents,
        "notes": notes,
        "dayRecords": day_records,
        "focusBlocks": focus_blocks,
        "tasks": tasks,
        "diagnostics": diagnostics,
    }


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Create a dry-run gbpDiary import bundle from an Obsidian vault.")
    parser.add_argument("vault", type=Path, help="Path to the Obsidian vault root")
    parser.add_argument("--output", "-o", type=Path, default=Path("obsidian-import-bundle.json"), help="Output JSON path")
    parser.add_argument("--summary", action="store_true", help="Print counts to stdout")
    args = parser.parse_args(argv)

    vault = args.vault.expanduser().resolve()
    if not vault.is_dir():
        print(f"Vault path is not a directory: {vault}", file=sys.stderr)
        return 2
    bundle = build_bundle(vault)
    args.output.write_text(json.dumps(bundle, indent=2, sort_keys=True), encoding="utf-8")
    if args.summary:
        print(json.dumps(bundle["counts"], indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
