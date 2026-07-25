#!/usr/bin/env python3

import json
import os
import shutil
import tempfile
import unittest

import ingest_profiles


# A settings_2a profile whose stored advanced_shot describes a completely different
# shot from its scalars: three pour-over frames at 75 C against a declared 90 C
# pressure profile. This is the shape de1app's save_profile actually produces, since
# it writes the array out of the global ::settings.
LEGACY_PRESSURE_WITH_STALE_STEPS = """advanced_shot {{exit_if 0 flow 8.0 volume 0 \
max_flow_or_pressure 0 max_flow_or_pressure_range 0.6 transition fast \
exit_flow_under 0 temperature 75.00 weight 0 name {Stale pour over} pressure 0 \
pump flow sensor coffee exit_type flow_under exit_pressure_over 0 exit_flow_over 6 \
seconds 30.00 exit_pressure_under 0} {exit_if 0 flow 4.0 volume 0 \
max_flow_or_pressure 0 max_flow_or_pressure_range 0.6 transition fast \
exit_flow_under 0 temperature 54.00 weight 0 name {Stale decline} pressure 0 \
pump flow sensor coffee exit_type flow_under exit_pressure_over 0 exit_flow_over 6 \
seconds 40.00 exit_pressure_under 0}}
espresso_temperature_steps_enabled 1
author Decent
espresso_hold_time 4
preinfusion_time 20
espresso_pressure 8.6
espresso_decline_time 35
pressure_end 6.0
espresso_temperature 90.0
espresso_temperature_0 90.0
espresso_temperature_1 88.0
espresso_temperature_2 88.0
espresso_temperature_3 88.0
settings_profile_type settings_2a
preinfusion_flow_rate 8.0
preinfusion_stop_pressure 4.0
final_desired_shot_volume 36
final_desired_shot_weight 36
final_desired_shot_weight_advanced 60
final_desired_shot_volume_advanced 135
final_desired_shot_volume_advanced_count_start 7
profile_title {Stale Array Profile}
beverage_type espresso
maximum_pressure 0
maximum_flow 0
maximum_pressure_range_default 0.9
maximum_flow_range_default 1.0
tank_desired_water_temperature 0
"""

LEGACY_FLOW_EMPTY_ARRAY = """advanced_shot {}
author Decent
settings_profile_type settings_2b
espresso_temperature 90.0
preinfusion_time 25
preinfusion_flow_rate 8.0
preinfusion_stop_pressure 4.0
espresso_hold_time 20
espresso_decline_time 10
flow_profile_hold 2.0
flow_profile_decline 1.0
final_desired_shot_volume 36
final_desired_shot_weight 36
final_desired_shot_weight_advanced 0
final_desired_shot_volume_advanced 0
final_desired_shot_volume_advanced_count_start 0
profile_title {Empty Array Flow Profile}
beverage_type espresso
maximum_pressure 0
maximum_flow 0
tank_desired_water_temperature 0
"""

ADVANCED_PROFILE = """advanced_shot {{exit_if 0 flow 0 volume 0 \
max_flow_or_pressure 0 max_flow_or_pressure_range 0.6 transition fast \
exit_flow_under 0 temperature 92.00 weight 0 name {Stored frame} pressure 9.0 \
pump pressure sensor coffee exit_type flow_under exit_pressure_over 0 \
exit_flow_over 6 seconds 25.00 exit_pressure_under 0}}
author Decent
settings_profile_type settings_2c
espresso_temperature 92.0
final_desired_shot_volume 11
final_desired_shot_weight 22
final_desired_shot_weight_advanced 44
final_desired_shot_volume_advanced 55
final_desired_shot_volume_advanced_count_start 3
profile_title {Advanced Profile}
beverage_type espresso
tank_desired_water_temperature 0
"""


def write(directory, name, content):
    path = os.path.join(directory, name)
    with open(path, "w") as f:
        f.write(content)
    return path


class LegacyStepSynthesisTest(unittest.TestCase):
    """The stored advanced_shot is never authoritative for settings_2a/2b."""

    def setUp(self):
        self.profile = ingest_profiles.convert_profile(
            ingest_profiles.parse_tcl_profile(LEGACY_PRESSURE_WITH_STALE_STEPS)
        )

    def test_ignores_a_populated_stale_advanced_shot(self):
        names = [step["name"] for step in self.profile["steps"]]

        self.assertNotIn("Stale pour over", names)
        self.assertNotIn("Stale decline", names)

    def test_derives_frames_from_the_scalars_instead(self):
        # Golden values, not just names. The fixture mirrors de1app's default.tcl, so
        # this pins the arithmetic: the 2 s temperature bump split off preinfusion_time
        # 20, the 3 s forced rise decremented from espresso_hold_time 4 leaving 1, the
        # second forced rise decremented from espresso_decline_time 35 leaving 32, and
        # the decline running to pressure_end 6.0 rather than espresso_pressure 8.6.
        self.assertEqual(
            [
                (
                    step["name"],
                    step["seconds"],
                    step["temperature"],
                    step["pump"],
                    step["pressure"],
                    step["flow"],
                    step["exit"]["value"] if step.get("exit") else None,
                )
                for step in self.profile["steps"]
            ],
            [
                ("preinfusion temp boost", "2.0", "90.0", "flow", "1.0", "8.0", "4.0"),
                ("preinfusion", "18.0", "88.0", "flow", "1.0", "8.0", "4.0"),
                ("forced rise without limit", "3.0", "88.0", "pressure", "8.6", "0.0", None),
                ("rise and hold", "1.0", "88.0", "pressure", "8.6", "0.0", None),
                ("forced rise without limit", "3.0", "88.0", "pressure", "8.6", "0.0", None),
                ("decline", "32.0", "88.0", "pressure", "6.0", "0.0", None),
            ],
        )

    def test_no_frame_contradicts_the_declared_temperatures(self):
        temperatures = {step["temperature"] for step in self.profile["steps"]}

        self.assertEqual(temperatures, {"90.0", "88.0"})

    def test_takes_the_plain_stop_targets_not_the_advanced_spellings(self):
        self.assertEqual(self.profile["target_weight"], "36.0")
        self.assertEqual(self.profile["target_volume"], "36.0")

    def test_derives_the_preinfuse_frame_count_rather_than_reading_it(self):
        # The file says 7; the two generated preinfusion frames say 2.
        self.assertEqual(self.profile["target_volume_count_start"], "2")

    def test_emits_the_pressure_editor_type(self):
        self.assertEqual(self.profile["type"], "pressure")

    def test_a_legacy_profile_with_an_empty_array_is_still_ingestible(self):
        profile = ingest_profiles.convert_profile(
            ingest_profiles.parse_tcl_profile(LEGACY_FLOW_EMPTY_ARRAY)
        )

        self.assertEqual(
            [step["name"] for step in profile["steps"]],
            ["preinfusion", "hold", "decline"],
        )
        self.assertEqual(profile["type"], "flow")
        self.assertEqual(profile["target_weight"], "36.0")

    def test_a_non_numeric_field_fails_with_the_field_and_the_value(self):
        broken = LEGACY_FLOW_EMPTY_ARRAY.replace(
            "espresso_hold_time 20", "espresso_hold_time twenty"
        )

        with self.assertRaises(ValueError) as caught:
            ingest_profiles.parse_tcl_profile(broken)

        self.assertIn("espresso_hold_time", str(caught.exception))
        self.assertIn("twenty", str(caught.exception))

    def test_an_underivable_legacy_profile_fails_loudly(self):
        without_hold_time = "\n".join(
            line
            for line in LEGACY_FLOW_EMPTY_ARRAY.splitlines()
            if not line.startswith("espresso_hold_time")
        )

        with self.assertRaises(ValueError) as caught:
            ingest_profiles.parse_tcl_profile(without_hold_time)

        self.assertIn("espresso_hold_time", str(caught.exception))


class GeneratorBranchTest(unittest.TestCase):
    """The duration-dependent paths the shipped corpus actually exercises."""

    def frames(self, source):
        return [
            step["name"]
            for step in ingest_profiles.parse_tcl_profile(source)["steps"]
        ]

    def test_no_decline_frame_when_decline_time_is_zero(self):
        # Classic Italian espresso, Trendy 6 bar and Traditional lever all take this.
        source = LEGACY_PRESSURE_WITH_STALE_STEPS.replace(
            "espresso_decline_time 35", "espresso_decline_time 0"
        )

        self.assertEqual(
            self.frames(source),
            [
                "preinfusion temp boost",
                "preinfusion",
                "forced rise without limit",
                "rise and hold",
            ],
        )

    def test_no_forced_rise_when_hold_time_is_three_or_less(self):
        source = LEGACY_PRESSURE_WITH_STALE_STEPS.replace(
            "espresso_hold_time 4", "espresso_hold_time 3"
        ).replace("espresso_decline_time 35", "espresso_decline_time 0")

        self.assertEqual(
            self.frames(source),
            ["preinfusion temp boost", "preinfusion", "rise and hold"],
        )

    def test_decline_gets_the_forced_rise_when_hold_is_short(self):
        # hold_time 2 is never decremented, so the decline branch sees 2 < 3 and
        # splits its own 3 s rise off a 35 s decline.
        source = LEGACY_PRESSURE_WITH_STALE_STEPS.replace(
            "espresso_hold_time 4", "espresso_hold_time 2"
        )
        steps = ingest_profiles.parse_tcl_profile(source)["steps"]

        self.assertEqual(
            [s["name"] for s in steps],
            [
                "preinfusion temp boost",
                "preinfusion",
                "rise and hold",
                "forced rise without limit",
                "decline",
            ],
        )
        self.assertEqual(steps[-1]["seconds"], 32.0)

    def test_no_preinfusion_frames_when_preinfusion_time_is_zero(self):
        # GHC/manual pressure control ships this shape: preinfusion_time 0 and no
        # espresso_temperature_steps_enabled at all. The preinfusion scalars are read
        # lazily, so a profile that omits them entirely is still derivable — de1app
        # reads them inside the branch that emits the frame.
        source = "\n".join(
            line
            for line in LEGACY_PRESSURE_WITH_STALE_STEPS.splitlines()
            if not line.startswith(
                (
                    "preinfusion_flow_rate",
                    "preinfusion_stop_pressure",
                    "espresso_temperature_steps_enabled",
                )
            )
        ).replace("preinfusion_time 20", "preinfusion_time 0")
        profile = ingest_profiles.parse_tcl_profile(source)

        self.assertEqual(
            [s["name"] for s in profile["steps"]],
            [
                "forced rise without limit",
                "rise and hold",
                "forced rise without limit",
                "decline",
            ],
        )
        self.assertEqual(profile["number_of_preinfuse_frames"], 0)

    def test_temperature_stepping_is_compared_numerically_like_tcl(self):
        # Tcl's `== 1` is numeric, so "1.0" enables stepping. A string compare would
        # silently fall through to the single-temperature layout.
        source = LEGACY_PRESSURE_WITH_STALE_STEPS.replace(
            "espresso_temperature_steps_enabled 1",
            "espresso_temperature_steps_enabled 1.0",
        )

        self.assertEqual(self.frames(source)[0], "preinfusion temp boost")

    def test_stepping_disabled_uses_one_temperature_and_no_boost_frame(self):
        source = LEGACY_PRESSURE_WITH_STALE_STEPS.replace(
            "espresso_temperature_steps_enabled 1",
            "espresso_temperature_steps_enabled 0",
        )
        steps = ingest_profiles.parse_tcl_profile(source)["steps"]

        self.assertEqual(steps[0]["name"], "preinfusion")
        self.assertEqual(steps[0]["seconds"], 20.0)
        self.assertEqual({s["temperature"] for s in steps}, {90.0})

    def test_flow_decline_is_gated_on_hold_time_not_decline_time(self):
        # Reproduces de1app's own quirk (profile.tcl:301) deliberately. If someone
        # "fixes" it to gate on espresso_decline_time, this fails.
        no_hold = LEGACY_FLOW_EMPTY_ARRAY.replace(
            "espresso_hold_time 20", "espresso_hold_time 0"
        )

        self.assertEqual(self.frames(no_hold), ["preinfusion"])

        no_decline = LEGACY_FLOW_EMPTY_ARRAY.replace(
            "espresso_decline_time 10", "espresso_decline_time 0"
        )
        steps = ingest_profiles.parse_tcl_profile(no_decline)["steps"]

        self.assertEqual([s["name"] for s in steps], ["preinfusion", "hold", "decline"])
        self.assertEqual(steps[-1]["seconds"], 0.0)


class LimiterTest(unittest.TestCase):
    """A dropped limiter is an unbounded pull; six shipped profiles carry one."""

    def test_pressure_profile_attaches_the_flow_limiter_to_hold_and_decline(self):
        source = LEGACY_PRESSURE_WITH_STALE_STEPS.replace(
            "maximum_flow 0", "maximum_flow 6.0"
        )
        steps = ingest_profiles.parse_tcl_profile(source)["steps"]

        limited = {s["name"]: s.get("limiter") for s in steps}
        self.assertEqual(limited["rise and hold"], {"value": 6.0, "range": 1.0})
        self.assertEqual(limited["decline"], {"value": 6.0, "range": 1.0})
        self.assertIsNone(limited["preinfusion"])
        self.assertIsNone(limited["forced rise without limit"])

    def test_flow_profile_attaches_the_pressure_limiter(self):
        source = LEGACY_FLOW_EMPTY_ARRAY.replace(
            "maximum_pressure 0", "maximum_pressure 8.6"
        )
        steps = ingest_profiles.parse_tcl_profile(source)["steps"]

        limited = {s["name"]: s.get("limiter") for s in steps}
        self.assertEqual(limited["hold"], {"value": 8.6, "range": 0.9})
        self.assertEqual(limited["decline"], {"value": 8.6, "range": 0.9})

    def test_falls_back_to_de1app_range_defaults_when_the_source_omits_them(self):
        source = "\n".join(
            line
            for line in LEGACY_PRESSURE_WITH_STALE_STEPS.splitlines()
            if not line.startswith("maximum_flow_range_default")
        ).replace("maximum_flow 0", "maximum_flow 6.0")
        steps = ingest_profiles.parse_tcl_profile(source)["steps"]

        hold = next(s for s in steps if s["name"] == "rise and hold")
        self.assertEqual(hold["limiter"]["range"], ingest_profiles.MAXIMUM_FLOW_RANGE_DEFAULT)


class AdvancedProfileTest(unittest.TestCase):
    """settings_2c keeps its stored frames and its _advanced stop targets."""

    def setUp(self):
        self.profile = ingest_profiles.convert_profile(
            ingest_profiles.parse_tcl_profile(ADVANCED_PROFILE)
        )

    def test_uses_the_stored_frames_as_is(self):
        self.assertEqual(
            [step["name"] for step in self.profile["steps"]], ["Stored frame"]
        )

    def test_takes_the_advanced_stop_targets(self):
        self.assertEqual(self.profile["target_weight"], "44.0")
        self.assertEqual(self.profile["target_volume"], "55.0")
        self.assertEqual(self.profile["target_volume_count_start"], "3")

    def test_emits_the_advanced_editor_type(self):
        self.assertEqual(self.profile["type"], "advanced")


class BeverageTypeTest(unittest.TestCase):
    def test_carries_de1app_tea_and_filter_types_through_unflattened(self):
        for wire_name in ("tea", "tea_portafilter", "filter", "pourover"):
            source = ADVANCED_PROFILE.replace(
                "beverage_type espresso", f"beverage_type {wire_name}"
            )

            profile = ingest_profiles.convert_profile(
                ingest_profiles.parse_tcl_profile(source)
            )

            self.assertEqual(profile["beverage_type"], wire_name)

    def test_still_maps_descale_onto_cleaning(self):
        source = ADVANCED_PROFILE.replace(
            "beverage_type espresso", "beverage_type descale"
        )

        profile = ingest_profiles.convert_profile(
            ingest_profiles.parse_tcl_profile(source)
        )

        self.assertEqual(profile["beverage_type"], "cleaning")


class V2JsonInputTest(unittest.TestCase):
    """The legacy guard must key on content, not on file extension."""

    def test_refuses_a_legacy_v2_json_export(self):
        # de1app's legacy_profile_to_v2 writes exactly this: stored frames plus a
        # target_weight taken from final_desired_shot_weight_advanced. Deriving from
        # it is impossible (the scalars are not in the export), so the honest answer
        # is a refusal rather than copying the two things the TCL path rejects.
        export = {
            "title": "Legacy Export",
            "legacy_profile_type": "settings_2a",
            "beverage_type": "espresso",
            "target_weight": 60.0,
            "steps": [
                {
                    "name": "STALE FRAME",
                    "pump": "flow",
                    "transition": "fast",
                    "temperature": 75.0,
                    "sensor": "coffee",
                    "seconds": 30.0,
                }
            ],
        }

        with self.assertRaises(ValueError) as caught:
            ingest_profiles.convert_profile(export)

        self.assertIn("settings_2a", str(caught.exception))
        self.assertIn(".tcl", str(caught.exception))

    def test_accepts_an_advanced_v2_json_export(self):
        export = {
            "title": "Advanced Export",
            "legacy_profile_type": "settings_2c",
            "beverage_type": "espresso",
            "tank_temperature": 0,
            "target_weight": 36.0,
            "target_volume": 0,
            "target_volume_count_start": 0,
            "steps": [
                {
                    "name": "Stored frame",
                    "pump": "pressure",
                    "transition": "fast",
                    "temperature": 92.0,
                    "sensor": "coffee",
                    "seconds": 25.0,
                    "pressure": 9.0,
                }
            ],
        }

        converted = ingest_profiles.convert_profile(export)

        self.assertEqual([s["name"] for s in converted["steps"]], ["Stored frame"])


class EndToEndTest(unittest.TestCase):
    """The happy path: a .tcl in, a corpus file plus manifest entry out."""

    def setUp(self):
        self.root = tempfile.mkdtemp()
        self.out = os.path.join(self.root, "out")
        os.makedirs(self.out)

    def tearDown(self):
        shutil.rmtree(self.root)

    def test_writes_the_profile_the_manifest_entry_and_its_provenance(self):
        write(self.root, "legacy.tcl", LEGACY_PRESSURE_WITH_STALE_STEPS)

        exit_code = ingest_profiles.main_with_args(
            [os.path.join(self.root, "legacy.tcl"), "-o", self.out, "--update-manifest"]
        )

        self.assertEqual(exit_code, 0)
        with open(os.path.join(self.out, "legacy.json")) as f:
            written = json.load(f)
        self.assertEqual(written["title"], "Stale Array Profile")
        self.assertEqual(written["type"], "pressure")
        self.assertEqual(written["target_weight"], "36.0")
        self.assertNotIn("Stale pour over", [s["name"] for s in written["steps"]])

        with open(os.path.join(self.out, "manifest.json")) as f:
            manifest = json.load(f)
        self.assertIn("legacy.json", manifest["profiles"])
        self.assertIn("legacy.json", manifest["provenance"])

    def test_dry_run_writes_nothing(self):
        write(self.root, "legacy.tcl", LEGACY_PRESSURE_WITH_STALE_STEPS)

        exit_code = ingest_profiles.main_with_args(
            [os.path.join(self.root, "legacy.tcl"), "--dry-run"]
        )

        self.assertEqual(exit_code, 0)
        self.assertEqual(os.listdir(self.out), [])

    def test_a_failing_profile_leaves_the_corpus_untouched(self):
        write(self.root, "good.tcl", ADVANCED_PROFILE)
        write(
            self.root,
            "bad.tcl",
            LEGACY_FLOW_EMPTY_ARRAY.replace("espresso_hold_time 20", ""),
        )

        exit_code = ingest_profiles.main_with_args(
            [
                os.path.join(self.root, "good.tcl"),
                os.path.join(self.root, "bad.tcl"),
                "-o",
                self.out,
                "--update-manifest",
            ]
        )

        self.assertEqual(exit_code, 1)
        self.assertEqual(os.listdir(self.out), [])

    def test_an_input_set_that_resolves_to_nothing_is_an_error(self):
        empty = os.path.join(self.root, "empty")
        os.makedirs(empty)

        self.assertEqual(ingest_profiles.main_with_args([empty, "-o", self.out]), 1)


class SourceCollisionTest(unittest.TestCase):
    """A profile in two source directories is reported, never silently resolved."""

    def setUp(self):
        self.root = tempfile.mkdtemp()
        self.base = os.path.join(self.root, "profiles")
        self.plugin = os.path.join(self.root, "plugins", "A_Flow", "profiles")
        self.editor = os.path.join(self.root, "profile_editors", "A_Flow", "profiles")
        os.makedirs(self.base)
        os.makedirs(self.plugin)
        os.makedirs(self.editor)

    def tearDown(self):
        shutil.rmtree(self.root)

    def convert_all(self):
        by_output = {}
        for path in ingest_profiles.resolve_inputs([self.root]):
            converted = ingest_profiles.convert_profile(
                ingest_profiles.load_profile(path)
            )
            by_output.setdefault(
                ingest_profiles.output_filename_for(path), []
            ).append((path, converted))
        return by_output

    def test_a_de1plus_root_contributes_all_three_source_directories(self):
        base_path = write(self.base, "shadowed.tcl", ADVANCED_PROFILE)
        plugin_path = write(self.plugin, "shadowed.tcl", ADVANCED_PROFILE)
        editor_path = write(self.editor, "shadowed.tcl", ADVANCED_PROFILE)

        resolved = ingest_profiles.resolve_inputs([self.root])

        self.assertEqual(
            sorted(resolved), sorted([base_path, plugin_path, editor_path])
        )

    def test_a_source_that_fails_to_convert_does_not_hand_the_slot_to_the_other(self):
        # Otherwise the surviving copy is written as if it were the only source —
        # precedence by parseability, which is exactly what design D4 rejects.
        base_path = write(
            self.base, "shadowed.tcl", ADVANCED_PROFILE.replace("seconds 25.00", "seconds 30.00")
        )
        broken_path = write(
            self.plugin,
            "shadowed.tcl",
            ADVANCED_PROFILE.replace("final_desired_shot_weight_advanced 44", ""),
        )
        output_dir = os.path.join(self.root, "out")
        os.makedirs(output_dir)

        exit_code = ingest_profiles.main_with_args([self.root, "-o", output_dir])

        self.assertEqual(exit_code, 1)
        self.assertEqual(os.listdir(output_dir), [])
        del base_path, broken_path

    def test_disagreeing_copies_are_reported_with_every_path(self):
        base_path = write(self.base, "shadowed.tcl", ADVANCED_PROFILE)
        plugin_path = write(
            self.plugin,
            "shadowed.tcl",
            ADVANCED_PROFILE.replace("seconds 25.00", "seconds 30.00"),
        )

        collisions = ingest_profiles.find_collisions(self.convert_all())

        self.assertEqual(list(collisions), ["shadowed.json"])
        self.assertEqual(sorted(collisions["shadowed.json"]), sorted([base_path, plugin_path]))

    def test_identical_copies_in_two_directories_are_not_an_error(self):
        write(self.base, "shadowed.tcl", ADVANCED_PROFILE)
        write(self.plugin, "shadowed.tcl", ADVANCED_PROFILE)

        self.assertEqual(ingest_profiles.find_collisions(self.convert_all()), {})

    def test_a_collision_writes_no_output_file(self):
        write(self.base, "shadowed.tcl", ADVANCED_PROFILE)
        write(
            self.plugin,
            "shadowed.tcl",
            ADVANCED_PROFILE.replace("seconds 25.00", "seconds 30.00"),
        )
        output_dir = os.path.join(self.root, "out")
        os.makedirs(output_dir)

        exit_code = ingest_profiles.main_with_args(
            [self.root, "-o", output_dir]
        )

        self.assertEqual(exit_code, 1)
        self.assertEqual(os.listdir(output_dir), [])


class ProvenanceTest(unittest.TestCase):
    def test_records_the_source_path_and_revision(self):
        provenance = ingest_profiles.source_provenance(__file__)

        self.assertTrue(provenance["source"].endswith("tools/ingest_profiles_test.py"))
        self.assertEqual(len(provenance["revision"]), 40)

    def test_manifest_carries_provenance_for_every_bundled_profile(self):
        corpus = os.path.join(
            os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
            "assets",
            "defaultProfiles",
        )
        with open(os.path.join(corpus, "manifest.json")) as f:
            manifest = json.load(f)

        provenance = manifest.get("provenance", {})
        missing = [name for name in manifest["profiles"] if name not in provenance]
        self.assertEqual(missing, [], f"no provenance recorded for {missing}")

        # An entry that names a repository must also name the commit in it, or the
        # record cannot answer "which source produced this?" without an experiment.
        incomplete = [
            name
            for name, entry in provenance.items()
            if "repository" in entry and "revision" not in entry
        ]
        self.assertEqual(incomplete, [], f"repository without revision: {incomplete}")

        # And no entry may leak a machine-local absolute path into shipped assets.
        absolute = [
            name for name, entry in provenance.items() if entry["source"].startswith("/")
        ]
        self.assertEqual(absolute, [], f"absolute source paths: {absolute}")


if __name__ == "__main__":
    unittest.main()
