#!/usr/bin/env python3
"""Tests for publish_data.py's version guard: python3 MW4CamoTracker/Tools/test_publish_data.py

The is_newer table is the same as DataServiceTests.versionsCompareNumberByNumber,
so the script and the app agree on what an installed app will fetch.
"""
import unittest

import publish_data as publish


class VersionTests(unittest.TestCase):
    def test_is_newer_matches_the_app(self):
        for version, known, newer in [
            ("0.9.12", "0.9.11", True),
            ("0.10.0", "0.9.11", True),
            ("1", "0.9.11", True),
            ("0.9.11.1", "0.9.11", True),
            ("0.9.11", "0.9.11", False),
            ("0.9.11.0", "0.9.11", False),
            ("0.9.1", "0.9.11", False),
            ("0.9.11a", "0.9.11", False),
            ("1.0.0-hotfix", "1.0.0", False),
            ("2026-11-03", "0.9.11", False),
        ]:
            with self.subTest(version=version, known=known):
                self.assertEqual(publish.is_newer(version, known), newer)

    def test_any_version_beats_none(self):
        self.assertTrue(publish.is_newer("0.0.1", None))

    def test_parts_read_as_swift_int(self):
        self.assertEqual(publish.swift_int("+5"), 5)
        self.assertEqual(publish.swift_int("11a"), 0)
        self.assertEqual(publish.swift_int(" 5"), 0)
        self.assertEqual(publish.swift_int("9" * 30), 0)
        # Swift's split drops empty parts: "1..2" is [1, 2]
        self.assertTrue(publish.is_newer("1..2", "1.1"))

    def test_only_dotted_numbers_are_plain(self):
        for version in ["0.9.12", "1", "10.0.3"]:
            self.assertTrue(publish.plain_version(version), version)
        for version in ["0.9.11a", "1.0.0-hotfix", "v1.0", "1..2", "1.", "", None, 1.2]:
            self.assertFalse(publish.plain_version(version), version)


class LiveGuardTests(unittest.TestCase):
    def problems(self, new, live):
        return publish.live_problems("warzone.json", {"version": new, "x": 1}, live, "jsDelivr")

    def test_higher_than_live_passes(self):
        self.assertEqual(self.problems("0.8.20", {"version": "0.8.19", "x": 0}), [])
        self.assertEqual(self.problems("0.10.0", {"version": "0.9.11", "x": 0}), [])

    def test_unchanged_or_unpublished_passes(self):
        self.assertEqual(self.problems("0.8.19", {"version": "0.8.19", "x": 1}), [])
        self.assertEqual(self.problems("0.8.19", None), [])

    def test_not_higher_than_live_is_refused(self):
        for new in ["0.8.19", "0.8.18", "0.8.1", "0.8.19a"]:
            with self.subTest(new=new):
                found = self.problems(new, {"version": "0.8.19", "x": 0})
                self.assertEqual(len(found), 1)
                self.assertIn("not higher than the live 0.8.19", found[0])

    def test_typo_after_double_digits_is_refused(self):
        # 0.9.1 after 0.9.10 looks newer to a person, not to the app
        self.assertEqual(len(self.problems("0.9.1", {"version": "0.9.10", "x": 0})), 1)


if __name__ == "__main__":
    unittest.main()
