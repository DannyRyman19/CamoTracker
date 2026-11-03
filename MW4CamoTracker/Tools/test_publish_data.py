#!/usr/bin/env python3
"""Tests for publish_data.py's guards: python3 MW4CamoTracker/Tools/test_publish_data.py

The is_newer table is the same as DataServiceTests.versionsCompareNumberByNumber,
so the script and the app agree on what an installed app will fetch. The rest
build small files in memory, so nothing here reads or writes Data/.
"""
import copy
import json
import tempfile
import unittest
from pathlib import Path

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


def text(en):
    return {"en": en}


def camo(item_id, children=(), **extra):
    return {"itemId": item_id, "name": text(f"Camo {item_id}"), "children": list(children), **extra}


def catalog(prestige=("Pyroclast", "Terminus"), stages=1):
    return {
        "version": "1.0",
        "weaponPrestige": [{"name": text(f"Prestige {i + 1}"), "maxLevel": None} for i in range(stages)],
        "prestigeCamos": [{"name": text(name)} for name in prestige],
        "categories": [{"categoryId": 0, "name": text("Assault Rifles"), "weapons": [
            {"weaponId": 1, "name": {lang: "M4" for lang in publish.LANGS}, "imageURL": "x", "maxLevel": 50},
        ]}],
    }


def mode_file(mode="multiplayer", objectives=None, **extra):
    return {"version": "1.0", "mode": mode, "weaponCamos": [{"weaponId": 1, "camos": [camo(1), camo(2)]}],
            "objectives": objectives if objectives is not None else [], **extra}


def guide():
    return {
        "version": "1.0",
        "map": {"image": "hajin_map.jpg"},
        "threatLevels": ["Low", {"en": "High", "de": "Hoch"}],
        "categories": [{"id": "key", "name": "Keys", "symbol": "key", "color": "#fff", "visible": True}],
        "markers": [{"id": "m1", "cat": "key", "name": "Door", "x": 0.5, "y": 1}],
        "guide": [
            {"id": "ops", "title": "Ops", "symbol": "list", "rows": [
                {"title": "Op A", "check": "op-a", "prints": [{"item": "plate", "qty": 2}]},
                {"title": "Op B", "check": "op-b", "links": ["scrap"]},
            ]},
            {"id": "gunsmith", "title": "Gunsmith", "symbol": "gun", "rows": [
                {"title": "M4", "weapon": 1, "subtitle": "Manual"},
                {"title": "Pistol", "weapon": 2, "subtitle": "Starter weapon"},
            ]},
        ],
        "items": [
            {"id": "scrap", "name": "Scrap", "kind": "Resource"},
            {"id": "plate", "name": "Plate", "kind": "Gear", "cost": [{"item": "scrap", "qty": 3}],
             "blueprint": True, "foundPlaces": ["m1"]},
            {"id": "bank-1", "name": "Bank I", "kind": "FOB Upgrade", "marker": "m1"},
        ],
        "traitTrees": [{"id": "scout", "name": "Scout", "color": "#0f0", "shape": "circle",
                        "rows": [["t1", None]], "emblem": "t1"}],
        "traits": [{"id": "t1", "name": None}],
    }


class DecodeTests(unittest.TestCase):
    def mode_problems(self, data):
        return publish.decode_problems("dmz.json", data, publish.MODE_FILE)

    def test_real_shapes_decode(self):
        self.assertEqual(self.mode_problems(mode_file()), [])
        self.assertEqual(publish.decode_problems("weapons.json", catalog(), publish.WEAPON_CATALOG), [])
        self.assertEqual(publish.decode_problems("hajin.json", guide(), publish.HAJIN_GUIDE), [])

    def test_missing_children_fails(self):
        data = mode_file()
        del data["weaponCamos"][0]["camos"][1]["children"]
        self.assertEqual(self.mode_problems(data),
                         ["dmz.json: weaponCamos[0].camos[1].children: missing (the app can't decode this file)"])

    def test_missing_objectives_fails(self):
        data = mode_file()
        del data["objectives"]
        self.assertEqual(self.mode_problems(data), ["dmz.json: objectives: missing (the app can't decode this file)"])

    def test_float_for_an_int_fails(self):
        data = mode_file()
        data["weaponCamos"][0]["camos"][0]["requirement"] = {"amount": 1.5, "unit": "kills", "description": text("x")}
        found = self.mode_problems(data)
        self.assertEqual(len(found), 1)
        self.assertIn("weaponCamos[0].camos[0].requirement.amount: expected an Int, got 1.5", found[0])
        # A whole number written 3.0 decodes; a string or a Bool doesn't
        data["weaponCamos"][0]["camos"][0]["requirement"]["amount"] = 3.0
        self.assertEqual(self.mode_problems(data), [])
        for wrong in ["3", True]:
            data["weaponCamos"][0]["camos"][0]["requirement"]["amount"] = wrong
            self.assertEqual(len(self.mode_problems(data)), 1, wrong)

    def test_null_required_field_fails_but_null_optional_passes(self):
        data = mode_file()
        data["weaponCamos"][0]["camos"][0]["imageURL"] = None      # String?
        self.assertEqual(self.mode_problems(data), [])
        data["weaponCamos"][0]["weaponId"] = None                   # Int
        self.assertEqual(self.mode_problems(data),
                         ["dmz.json: weaponCamos[0].weaponId: null, but the app needs a value (the app can't decode this file)"])

    def test_wrong_type_in_an_optional_still_fails(self):
        data = mode_file(hidden="yes")
        self.assertIn("hidden: expected true or false", self.mode_problems(data)[0])

    def test_guide_text_is_a_string_or_an_object_of_strings(self):
        data = guide()
        data["markers"][0]["name"] = {"en": "Door", "de": "Tür"}
        self.assertEqual(publish.decode_problems("hajin.json", data, publish.HAJIN_GUIDE), [])
        for wrong in [{"en": 1}, ["Door"], 3, None]:
            data["markers"][0]["name"] = wrong
            found = publish.decode_problems("hajin.json", data, publish.HAJIN_GUIDE)
            self.assertEqual(len(found), 1, wrong)
            self.assertIn("markers[0].name:", found[0])

    def test_trait_tree_rows_take_null_slots(self):
        data = guide()
        data["traitTrees"][0]["rows"] = [[None, None, "t1"], []]
        self.assertEqual(publish.decode_problems("hajin.json", data, publish.HAJIN_GUIDE), [])
        data["traitTrees"][0]["rows"] = [[1]]
        self.assertEqual(len(publish.decode_problems("hajin.json", data, publish.HAJIN_GUIDE)), 1)

    def test_localized_text_must_be_an_object(self):
        data = catalog()
        data["categories"][0]["weapons"][0]["name"] = "M4"
        self.assertIn("categories[0].weapons[0].name: expected an object",
                      publish.decode_problems("weapons.json", data, publish.WEAPON_CATALOG)[0])

    def test_manifest_shape(self):
        manifest = {"catalog": {"version": "1", "path": "weapons.json"}, "modes": {"dmz": {"version": "1", "path": "dmz.json"}},
                    "notification": {"silent": True}}
        self.assertEqual(publish.decode_problems("manifest.json", manifest, publish.MANIFEST), [])
        manifest["modes"]["dmz"]["version"] = 1
        self.assertEqual(len(publish.decode_problems("manifest.json", manifest, publish.MANIFEST)), 1)

    def test_a_flood_is_capped(self):
        data = mode_file()
        data["weaponCamos"] = [{"weaponId": i, "camos": [{"itemId": 1, "name": text("x")}]} for i in range(30)]
        found = self.mode_problems(data)
        self.assertEqual(len(found), publish.DECODE_LIMIT + 1)
        self.assertIn("...and 20 more", found[-1])


class GuideTests(unittest.TestCase):
    def run_check(self, data):
        problems, warnings = [], []
        publish.check_guide(problems, warnings, data)
        return problems, warnings

    def test_clean_guide_passes(self):
        self.assertEqual(self.run_check(guide()), ([], []))

    def test_duplicate_ids(self):
        data = guide()
        data["items"].append(copy.deepcopy(data["items"][0]))
        data["markers"].append(copy.deepcopy(data["markers"][0]))
        problems, _ = self.run_check(data)
        self.assertIn("hajin.json: duplicate markers id ['m1']", problems)
        self.assertIn("hajin.json: duplicate items id ['scrap']", problems)

    def test_duplicate_check_keys(self):
        data = guide()
        data["guide"][1]["rows"][0]["check"] = "op-a"
        problems, _ = self.run_check(data)
        self.assertEqual(problems, ["hajin.json: rows share check key ['op-a']; ticking one would tick the other"])

    def test_dangling_links_are_errors(self):
        data = guide()
        data["markers"][0]["cat"] = "nope"
        data["items"][1]["cost"][0]["item"] = "gone"
        data["guide"][0]["rows"][1]["links"] = ["gone-too"]
        data["guide"][0]["rows"][0]["prints"][0]["item"] = "gone-three"
        problems, _ = self.run_check(data)
        self.assertEqual(len(problems), 4, problems)

    def test_soft_references_warn(self):
        data = guide()
        data["items"][1]["foundPlaces"] = ["nowhere"]
        data["traitTrees"][0]["emblem"] = "t9"
        problems, warnings = self.run_check(data)
        self.assertEqual(problems, [])
        self.assertEqual(len(warnings), 2)

    def test_saved_keys(self):
        self.assertEqual(publish.guide_keys(guide()), {
            "op-a", "op-b", "manual-1", "scrap", "plate", "bank-1", "blueprint-plate", "upgrade-bank-1"})


class RemovedKeyTests(unittest.TestCase):
    def removed(self, before, now, allowed=()):
        warnings, notes = [], []
        gone = publish.removed_keys(warnings, notes, "hajin.json", publish.guide_keys(before), publish.guide_keys(now), set(allowed))
        return gone, warnings, notes

    def test_nothing_removed_is_silent(self):
        self.assertEqual(self.removed(guide(), guide()), ([], [], []))

    def test_adding_is_silent(self):
        now = guide()
        now["guide"][0]["rows"].append({"title": "Op C", "check": "op-c"})
        self.assertEqual(self.removed(guide(), now), ([], [], []))

    def test_removed_keys_warn_loudly(self):
        now = guide()
        del now["guide"][0]["rows"][1]                 # op-b
        now["items"][1]["blueprint"] = False           # blueprint-plate
        gone, warnings, notes = self.removed(guide(), now)
        self.assertEqual(gone, ["blueprint-plate", "op-b"])
        self.assertEqual(notes, [])
        self.assertEqual(len(warnings), 1)
        self.assertTrue(warnings[0].startswith("WARNING: hajin.json drops 2 saved tick key(s)"))
        self.assertIn("--allow-removed blueprint-plate,op-b", warnings[0])

    def test_acknowledged_removals_are_a_note(self):
        now = guide()
        del now["guide"][0]["rows"][1]
        now["items"][1]["blueprint"] = False
        _, warnings, notes = self.removed(guide(), now, ["op-b"])
        self.assertEqual(len(notes), 1)
        self.assertIn("op-b", notes[0])
        self.assertIn("blueprint-plate", warnings[0])
        self.assertNotIn("op-b", warnings[0])
        _, warnings, notes = self.removed(guide(), now, ["all"])
        self.assertEqual(warnings, [])
        self.assertEqual(len(notes), 1)

    def test_objective_keys_walk_children(self):
        data = mode_file("dmz", objectives=[{"categoryId": 3, "name": text("Ops"), "items": [camo(1, [camo(2)])]}])
        self.assertEqual(publish.objective_keys("dmz", data), {"obj|dmz|3|1", "obj|dmz|3|2"})


class PrestigeTests(unittest.TestCase):
    def problems(self, now, published):
        problems, warnings = [], []
        publish.check_catalog(problems, warnings, now, published)
        return problems

    def test_append_passes(self):
        self.assertEqual(self.problems(catalog(("Pyroclast", "Terminus", "Scatter")), catalog()), [])

    def test_reorder_is_an_error(self):
        found = self.problems(catalog(("Terminus", "Pyroclast")), catalog())
        self.assertEqual(len(found), 2)
        self.assertIn("prestigeCamos order is saved progress", found[0])

    def test_removing_is_an_error(self):
        found = self.problems(catalog(("Pyroclast",)), catalog())
        self.assertEqual(len(found), 1)
        self.assertIn("prestigeCamos[1] (Terminus) is published but missing now", found[0])

    def test_stage_within_weapon_prestige(self):
        data = catalog()
        data["prestigeCamos"][0]["stage"] = 2
        self.assertIn("has stage 2, but weaponPrestige has 1 stage(s)", self.problems(data, None)[0])
        data["prestigeCamos"][0]["stage"] = 1
        self.assertEqual(self.problems(data, None), [])


class ModeTests(unittest.TestCase):
    MODES = ["multiplayer", "warzone", "dmz"]

    def problems(self, data, published=None, allow=False, files=None):
        problems, warnings, notes = [], [], []
        files = files or {data["mode"]: data}
        publish.check_mode(problems, warnings, data["mode"], data, [1], published, self.MODES, files, allow, notes)
        return problems, notes

    def test_clean_mode_passes(self):
        self.assertEqual(self.problems(mode_file(), mode_file()), ([], []))

    def test_track_from_unknown_or_itself(self):
        self.assertIn("isn't one of this game's modes", self.problems(mode_file("warzone", trackFrom="zombies"))[0][0])
        self.assertIn("names the mode itself", self.problems(mode_file("warzone", trackFrom="warzone"))[0][0])
        self.assertEqual(self.problems(mode_file("warzone", trackFrom="multiplayer"))[0], [])

    def test_track_from_chained(self):
        files = {"multiplayer": mode_file(trackFrom="dmz"), "warzone": mode_file("warzone", trackFrom="multiplayer")}
        found, _ = self.problems(files["warzone"], files=files)
        self.assertIn("the app doesn't chain them", found[0])

    def test_track_from_change_needs_acknowledging(self):
        for before, after in [(None, "multiplayer"), ("multiplayer", None), ("multiplayer", "dmz")]:
            published = mode_file("warzone", **({"trackFrom": before} if before else {}))
            now = mode_file("warzone", **({"trackFrom": after} if after else {}))
            found, _ = self.problems(now, published)
            self.assertEqual(len(found), 1, (before, after))
            self.assertIn("--allow-trackfrom-change", found[0])
            found, notes = self.problems(now, published, allow=True)
            self.assertEqual(found, [])
            self.assertEqual(len(notes), 1)

    def test_duplicate_objective_ids(self):
        objectives = [
            {"categoryId": 3, "name": text("A"), "items": [camo(1), camo(1)]},
            {"categoryId": 3, "name": text("B"), "items": [camo(2, [camo(5), camo(5)])]},
        ]
        found, _ = self.problems(mode_file("dmz", objectives=objectives))
        self.assertEqual(found, [
            "dmz.json: duplicate objectives categoryId [3]",
            "dmz.json: duplicate itemId [1] in objectives category 3",
            "dmz.json: duplicate itemId [5] in objectives category 3 > item 2's children",
        ])

    def test_counter_must_name_a_camo_of_the_weapon(self):
        data = mode_file()
        data["weaponCamos"][0]["camos"][1]["counter"] = 1
        self.assertEqual(self.problems(data)[0], [])
        data["weaponCamos"][0]["camos"][1]["counter"] = 9
        self.assertIn("has counter 9", self.problems(data)[0][0])

    def test_duplicate_weapon_entries(self):
        data = mode_file()
        data["weaponCamos"].append(copy.deepcopy(data["weaponCamos"][0]))
        self.assertIn("more than one weaponCamos entry for weaponId [1]", self.problems(data)[0][0])

    def test_removed_camo_is_still_an_error(self):
        published = mode_file()
        data = mode_file()
        del data["weaponCamos"][0]["camos"][1]
        self.assertIn("lost camo itemId [2]", self.problems(data, published)[0][0])


class CheckTests(unittest.TestCase):
    """check() itself, on files in a temporary folder standing in for
    Resources/ and the published Data/MW4/."""

    def setUp(self):
        self.saved = (publish.RES, publish.OUT, publish.MODES, publish.GUIDES, publish.PREFIX)
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        publish.RES, publish.OUT = Path(folder.name, "res"), Path(folder.name, "out")
        publish.RES.mkdir()
        publish.OUT.mkdir()
        publish.MODES, publish.GUIDES, publish.PREFIX = ["multiplayer"], ["hajin"], ""
        self.write(publish.RES, catalog(), mode_file(), guide())
        self.write(publish.OUT, catalog(), mode_file(), guide())

    def tearDown(self):
        publish.RES, publish.OUT, publish.MODES, publish.GUIDES, publish.PREFIX = self.saved

    def write(self, folder, weapons, multiplayer, hajin):
        for name, data in (("weapons", weapons), ("multiplayer", multiplayer), ("hajin", hajin)):
            (folder / f"{name}.json").write_text(json.dumps(data), encoding="utf-8")

    def run_check(self, **flags):
        problems, warnings, notes = [], [], []
        publish.check(problems, warnings, notes, **flags)
        return problems, warnings, notes

    def test_unchanged_files_pass(self):
        self.assertEqual(self.run_check(), ([], [], []))

    def test_a_file_the_app_cant_decode_is_reported_first(self):
        broken = mode_file()
        del broken["objectives"]
        self.write(publish.RES, catalog(), broken, guide())
        problems, _, _ = self.run_check()
        self.assertEqual(problems, ["multiplayer.json: objectives: missing (the app can't decode this file)"])

    def test_removed_guide_keys_and_the_flag(self):
        now = guide()
        del now["guide"][0]["rows"][1]
        self.write(publish.RES, catalog(), mode_file(), now)
        problems, warnings, notes = self.run_check()
        self.assertEqual(problems, [])
        self.assertIn("op-b", warnings[0])
        problems, warnings, notes = self.run_check(allow_removed=["op-b", "op-z"])
        self.assertEqual(len(notes), 1)
        self.assertEqual(warnings, ["--allow-removed op-z: no published key by that name is being removed (a typo?)"])


if __name__ == "__main__":
    unittest.main()
