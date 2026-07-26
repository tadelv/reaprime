#!/usr/bin/env python3

import unittest

import ingest_profiles


STORED_FRAME = """{{exit_if 0 flow 0 volume 0 max_flow_or_pressure 0 max_flow_or_pressure_range 0 transition fast exit_flow_under 0 temperature 92 weight 0 name {Stored frame} pressure 9 pump pressure sensor coffee exit_type flow_under exit_pressure_over 0 exit_flow_over 0 seconds 10 exit_pressure_under 0}}"""


def tcl_profile(settings_type, advanced_shot):
    return f"""advanced_shot {advanced_shot}
author Decent
settings_profile_type {settings_type}
final_desired_shot_weight_advanced 36
final_desired_shot_volume_advanced 0
final_desired_shot_volume_advanced_count_start 0
profile_title {{Test profile}}
beverage_type espresso
tank_desired_water_temperature 0
"""


class LegacyProfileGuardTest(unittest.TestCase):
    def test_rejects_legacy_simple_profiles_with_empty_or_stored_frames(self):
        for settings_type in ("settings_2a", "settings_2b"):
            for advanced_shot in ("{}", STORED_FRAME):
                with self.subTest(
                    settings_type=settings_type,
                    populated=advanced_shot != "{}",
                ):
                    with self.assertRaisesRegex(
                        ValueError,
                        r"advanced_shot.*not authoritative.*does not regenerate.*final advanced-profile JSON",
                    ):
                        ingest_profiles.parse_tcl_profile(
                            tcl_profile(settings_type, advanced_shot)
                        )

    def test_ingests_an_ordinary_advanced_profile(self):
        profile = ingest_profiles.convert_profile(
            ingest_profiles.parse_tcl_profile(
                tcl_profile("settings_2c", STORED_FRAME)
            )
        )

        self.assertEqual([step["name"] for step in profile["steps"]], ["Stored frame"])


if __name__ == "__main__":
    unittest.main()
