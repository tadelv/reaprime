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
        self.assertEqual(
            [step["name"] for step in self.profile["steps"]],
            [
                "preinfusion temp boost",
                "preinfusion",
                "forced rise without limit",
                "rise and hold",
                "forced rise without limit",
                "decline",
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

    def test_an_underivable_legacy_profile_fails_loudly(self):
        without_hold_time = "\n".join(
            line
            for line in LEGACY_FLOW_EMPTY_ARRAY.splitlines()
            if not line.startswith("espresso_hold_time")
        )

        with self.assertRaises(ValueError) as caught:
            ingest_profiles.parse_tcl_profile(without_hold_time)

        self.assertIn("espresso_hold_time", str(caught.exception))


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


class SourceCollisionTest(unittest.TestCase):
    """A profile in two source directories is reported, never silently resolved."""

    def setUp(self):
        self.root = tempfile.mkdtemp()
        self.base = os.path.join(self.root, "profiles")
        self.plugin = os.path.join(self.root, "plugins", "A_Flow", "profiles")
        os.makedirs(self.base)
        os.makedirs(self.plugin)

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

    def test_a_de1plus_root_contributes_base_and_plugin_directories(self):
        base_path = write(self.base, "shadowed.tcl", ADVANCED_PROFILE)
        plugin_path = write(self.plugin, "shadowed.tcl", ADVANCED_PROFILE)

        resolved = ingest_profiles.resolve_inputs([self.root])

        self.assertEqual(sorted(resolved), sorted([base_path, plugin_path]))

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

        missing = [
            name
            for name in manifest["profiles"]
            if name not in manifest.get("provenance", {})
        ]

        self.assertEqual(missing, [], f"no provenance recorded for {missing}")


if __name__ == "__main__":
    unittest.main()
