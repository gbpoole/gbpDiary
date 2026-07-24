#!/usr/bin/env python3
import tempfile
import unittest
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
import obsidian_import_bundle as importer


class ObsidianImportBundleTests(unittest.TestCase):
    def test_wikilink_normalization(self):
        self.assertEqual(
            importer.canonical_markdown_path('"[[CMS/People/Greg Poole|Greg Poole]]"'),
            "CMS/People/Greg Poole.md",
        )
        self.assertEqual(importer.display_name_from_link("[[CMS/Projects/Foo|Foo]]"), "Foo")

    def test_frontmatter_lists_and_body(self):
        frontmatter, body = importer.parse_frontmatter(
            "---\nType:\n  - project\nDevTeam:\n  - \"[[CMS/People/Ada|Ada]]\"\n---\nBody"
        )
        self.assertEqual(frontmatter["Type"], ["project"])
        self.assertEqual(frontmatter["DevTeam"], ['"[[CMS/People/Ada|Ada]]"'])
        self.assertEqual(body, "Body")

    def test_build_bundle_extracts_entities_relationships_and_tasks(self):
        with tempfile.TemporaryDirectory() as tmp:
            vault = Path(tmp)
            (vault / "CMS/People").mkdir(parents=True)
            (vault / "CMS/Projects").mkdir(parents=True)
            (vault / "CMS/Minutes/Foo").mkdir(parents=True)

            (vault / "CMS/Minutes/Foo/2025-08-20_14.28").mkdir(parents=True)
            (vault / "CMS/Minutes/Foo/2025-08-20_14.28/plot.png").write_bytes(b"png")

            (vault / "CMS/People/Greg Poole.md").write_text(
                "---\ntype:\n  - person\ntags:\n  - collaborator\nEmail: \"greg@example.com\"\n---\n",
                encoding="utf-8",
            )
            (vault / "CMS/People/Owen Cole.md").write_text(
                "---\ntype:\n  - person\n---\n",
                encoding="utf-8",
            )
            (vault / "CMS/People/Lee Spitler.md").write_text(
                "---\ntype:\n  - person\n---\n",
                encoding="utf-8",
            )
            (vault / "CMS/Projects/Foo.md").write_text(
                "---\ntype:\n  - project\nDevTeam:\n  - \"[[CMS/People/Greg Poole|Greg Poole]]\"\nDescription: Test project\n---\n",
                encoding="utf-8",
            )
            (vault / "CMS/Projects/YWang_2026A.md").write_text(
                "---\ntype:\n  - project\n---\n",
                encoding="utf-8",
            )
            (vault / "CMS/Minutes/Foo/2025-08-20_14.28.md").write_text(
                "---\ntype:\n  - meeting\ntags:\n  - weekly\nProject:\n  - \"[[CMS/Projects/Foo|Foo]]\"\nDate: 2025-08-20 14:28\nDuration: 1h\nAttendees:\n  - \"[[CMS/People/Greg Poole|Greg Poole]]\"\nSummary: Status update\n---\n\n## Notes\n- Useful #milestone note\n\n![[plot.png]]\n\nAfter image.\n## New Tasks\n- [ ] ( who::[[CMS/People/Greg Poole|Greg Poole]] ) Do thing [project::[[CMS/Projects/Foo|Foo]]]\n",
                encoding="utf-8",
            )
            (vault / "Diary").mkdir()
            (vault / "Diary/2025-08-21-Thursday.md").write_text(
                "---\ncreated: 2025-08-21 09:00\ntags:\n  - diary-tag\n---\n- [x] Timesheet focus (duration:: 1.5 h) #timesheet ✅ 2025-08-21\n    - [ ] Nested task\n    - [ ] [[CMS/People/Lee Spitler|Lee Spitler]] needs to be informed that he won't be able to apply for RT time next semester📅 2025-08-22\n- [?] Follow up focus (follow_up:: 2025-08-28)\n- [x] Apply for access to Nectar and OzSTAR projects (who::[[CMS/People/Owen Cole.md|Owen Cole]]) (project::[[CMS/Projects/YWang_2026A.md|YWang_2026A]]) ✅ 2026-03-02\n",
                encoding="utf-8",
            )

            bundle = importer.build_bundle(vault)

            self.assertEqual(bundle["counts"]["people"], 3)
            self.assertEqual(bundle["counts"]["projects"], 2)
            self.assertEqual(bundle["counts"]["minutes"], 1)
            self.assertEqual(bundle["counts"]["focusBlocks"], 3)
            self.assertEqual(bundle["counts"]["tasks"], 3)
            self.assertEqual(bundle["people"][0]["email"], "greg@example.com")
            self.assertEqual(bundle["people"][0]["tags"], ["collaborator"])
            self.assertEqual(bundle["projects"][0]["description"], "Test project")
            self.assertEqual(bundle["minutes"][0]["duration"]["hoursNormalized"], 1.0)
            minutes_note = next(note for note in bundle["notes"] if note["sourceContext"]["sourceSection"] == "Notes")
            self.assertEqual(minutes_note["tags"], ["milestone", "weekly"])
            self.assertIn("#milestone", minutes_note["content"])
            self.assertNotIn("blocks", minutes_note)
            self.assertEqual(len(minutes_note["attachments"]), 1)
            self.assertEqual(minutes_note["attachments"][0]["ref"], "CMS/Minutes/Foo/2025-08-20_14.28/plot.png")
            # The image link is rewritten to an inline attachment:// ref in the markdown content.
            self.assertIn(f"attachment://{minutes_note['attachments'][0]['id']}", minutes_note["content"])
            diary_record = next(record for record in bundle["dayRecords"] if record["date"] == "2025-08-21")
            self.assertEqual(diary_record["tags"], ["diary-tag", "timesheet"])
            self.assertEqual(bundle["tasks"][0]["summary"], "Do thing")
            nested = next(task for task in bundle["tasks"] if task["summary"] == "Nested task")
            self.assertIsNotNone(nested["dayRecordId"])
            lee_task = next(task for task in bundle["tasks"] if task["summary"].startswith("Lee Spitler needs"))
            self.assertEqual(lee_task["summary"], "Lee Spitler needs to be informed that he won't be able to apply for RT time next semester")
            self.assertEqual(lee_task["scheduledAt"], "2025-08-22")
            self.assertIsNone(lee_task["assigneePersonId"])
            self.assertEqual(lee_task["notes"], "")
            timesheet = next(block for block in bundle["focusBlocks"] if block["summary"] == "Timesheet focus")
            self.assertEqual(timesheet["duration"]["hoursNormalized"], 1.5)
            self.assertEqual(timesheet["tags"], ["timesheet"])
            owen = next(block for block in bundle["focusBlocks"] if block["summary"] == "Apply for access to Nectar and OzSTAR projects")
            owen_person = next(person for person in bundle["people"] if person["name"] == "Owen Cole")
            ywang_project = next(project for project in bundle["projects"] if project["name"] == "YWang_2026A")
            self.assertEqual(owen["assigneePersonId"], owen_person["id"])
            self.assertEqual(owen["projectId"], ywang_project["id"])
            self.assertEqual(bundle["diagnostics"], [])


if __name__ == "__main__":
    unittest.main()
