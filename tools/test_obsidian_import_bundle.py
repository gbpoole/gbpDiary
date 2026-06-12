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

            (vault / "CMS/People/Greg Poole.md").write_text(
                "---\ntype:\n  - person\nEmail: \"greg@example.com\"\n---\n",
                encoding="utf-8",
            )
            (vault / "CMS/Projects/Foo.md").write_text(
                "---\ntype:\n  - project\nDevTeam:\n  - \"[[CMS/People/Greg Poole|Greg Poole]]\"\nDescription: Test project\n---\n",
                encoding="utf-8",
            )
            (vault / "CMS/Minutes/Foo/2025-08-20_14.28.md").write_text(
                "---\ntype:\n  - meeting\nProject:\n  - \"[[CMS/Projects/Foo|Foo]]\"\nDate: 2025-08-20 14:28\nDuration: 1h\nAttendees:\n  - \"[[CMS/People/Greg Poole|Greg Poole]]\"\nSummary: Status update\n---\n\n## Notes\n- Useful note\n## New Tasks\n- [ ] ( who::[[CMS/People/Greg Poole|Greg Poole]] ) Do thing [project::[[CMS/Projects/Foo|Foo]]]\n",
                encoding="utf-8",
            )
            (vault / "Diary").mkdir()
            (vault / "Diary/2025-08-21-Thursday.md").write_text(
                "---\ncreated: 2025-08-21 09:00\n---\n- [x] Timesheet task (duration:: 1.5 h) #timesheet ✅ 2025-08-21\n- [?] Follow up task (follow_up:: 2025-08-28)\n",
                encoding="utf-8",
            )

            bundle = importer.build_bundle(vault)

            self.assertEqual(bundle["counts"]["people"], 1)
            self.assertEqual(bundle["counts"]["projects"], 1)
            self.assertEqual(bundle["counts"]["minutes"], 1)
            self.assertEqual(bundle["counts"]["tasks"], 3)
            self.assertEqual(bundle["people"][0]["email"], "greg@example.com")
            self.assertEqual(bundle["projects"][0]["description"], "Test project")
            self.assertEqual(bundle["minutes"][0]["duration"]["hoursNormalized"], 1.0)
            self.assertEqual(bundle["tasks"][0]["summary"], "Do thing")
            timesheet = next(task for task in bundle["tasks"] if task["summary"] == "Timesheet task")
            self.assertEqual(timesheet["status"], "completed")
            self.assertEqual(timesheet["completedAt"], "2025-08-21")
            self.assertEqual(timesheet["duration"]["hoursNormalized"], 1.5)
            self.assertEqual(timesheet["tags"], ["timesheet"])
            follow_up = next(task for task in bundle["tasks"] if task["summary"] == "Follow up task")
            self.assertEqual(follow_up["status"], "followUpPending")
            self.assertEqual(follow_up["followUpAt"], "2025-08-28")
            self.assertEqual(bundle["diagnostics"], [])


if __name__ == "__main__":
    unittest.main()
