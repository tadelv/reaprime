#!/usr/bin/env python3
"""Ingest de1app TCL or v2 JSON profiles into Decent format.

Supports:
  - de1app TCL profiles with advanced_shot steps (e.g. from de1app/de1plus/profiles/)
  - v2 JSON profiles that already have steps
  - Legacy TCL profiles (settings_2a/2b), whose frames are derived from the profile's
    scalar fields the way de1app derives them at load time. The stored advanced_shot
    array is ignored for those types — de1app writes it out of the global ::settings,
    so it routinely describes a different profile entirely.

Usage:
    # Convert specific profiles (auto-detects format by extension)
    python3 tools/ingest_profiles.py path/to/profile.json -o assets/defaultProfiles/
    python3 tools/ingest_profiles.py path/to/profile.tcl -o assets/defaultProfiles/

    # Convert multiple profiles (mixed formats OK)
    python3 tools/ingest_profiles.py profiles/*.json de1app/profiles/*.tcl -o assets/defaultProfiles/

    # Dry run (print converted JSON to stdout)
    python3 tools/ingest_profiles.py path/to/profile.tcl --dry-run

    # Also update manifest.json
    python3 tools/ingest_profiles.py profiles/*.json -o assets/defaultProfiles/ --update-manifest
"""

import argparse
import glob
import json
import os
import re
import subprocess
import sys

# Valid beverage types in Decent, in de1app's wire spelling
VALID_BEVERAGE_TYPES = {
    "espresso",
    "calibrate",
    "cleaning",
    "manual",
    "pourover",
    "tea",
    "tea_portafilter",
    "filter",
}

# Mapping from source beverage types to ours
BEVERAGE_TYPE_MAP = {
    "descale": "cleaning",
}

LEGACY_PRESSURE_TYPE = "settings_2a"
LEGACY_FLOW_TYPE = "settings_2b"
LEGACY_TYPES = (LEGACY_PRESSURE_TYPE, LEGACY_FLOW_TYPE)

# de1app's editor type, from legacy_profile_to_v2 in de1plus/profile.tcl
EDITOR_TYPE_BY_SETTINGS_TYPE = {
    LEGACY_PRESSURE_TYPE: "pressure",
    LEGACY_FLOW_TYPE: "flow",
}

# de1app global ::settings defaults, from de1plus/machine.tcl. A legacy profile that
# omits one of these is generated against the default, exactly as de1app does.
TEMP_BUMP_TIME_SECONDS = 2.0
MAXIMUM_FLOW_RANGE_DEFAULT = 1.0
MAXIMUM_PRESSURE_RANGE_DEFAULT = 0.9


def strip_tcl_braces(value):
    """Remove TCL artifact curly braces from string values."""
    if isinstance(value, str) and value.startswith("{") and value.endswith("}"):
        return value[1:-1]
    return value


# ---------------------------------------------------------------------------
# Legacy step synthesis
#
# A port of pressure_to_advanced_list / flow_to_advanced_list from de1app's
# de1plus/profile.tcl. Rationale and the de1app line references live in
# doc/AI_STORAGE_NOTES.md.
# ---------------------------------------------------------------------------

def _optional_number(fields, key, default):
    """Read a numeric TCL field, falling back to a de1app global default."""
    raw = fields.get(key, "")
    if isinstance(raw, str):
        raw = raw.strip()
    if raw in ("", "{}", None):
        return default
    return float(raw)


def _required_number(fields, key):
    """Read a numeric TCL field that has no meaningful default."""
    raw = fields.get(key, "")
    if isinstance(raw, str):
        raw = raw.strip()
    if raw in ("", "{}", None):
        raise ValueError(
            f"Cannot derive frames: required field '{key}' is missing or empty"
        )
    try:
        return float(raw)
    except ValueError:
        raise ValueError(
            f"Cannot derive frames: field '{key}' is not a number (got '{raw}')"
        ) from None


def _preinfusion_frame_lengths(fields):
    """Return (first_frame_len, second_frame_len) and the four frame temperatures."""
    preinfusion_time = _required_number(fields, "preinfusion_time")
    steps_enabled = fields.get("espresso_temperature_steps_enabled", "").strip() == "1"

    if steps_enabled:
        bump = _optional_number(fields, "temp_bump_time_seconds", TEMP_BUMP_TIME_SECONDS)
        first_len = bump
        second_len = max(preinfusion_time - bump, 0.0)
        temps = [
            _required_number(fields, f"espresso_temperature_{i}") for i in range(4)
        ]
    else:
        first_len = 0.0
        second_len = preinfusion_time
        temps = [_required_number(fields, "espresso_temperature")] * 4

    return first_len, second_len, temps


def _preinfusion_steps(fields, first_len, second_len, temps, boost_name):
    """The one or two flow-pump preinfusion frames both generators share."""
    flow_rate = _required_number(fields, "preinfusion_flow_rate")
    stop_pressure = _required_number(fields, "preinfusion_stop_pressure")

    def frame(name, temperature, seconds):
        return {
            "name": name,
            "pump": "flow",
            "transition": "fast",
            "temperature": temperature,
            "sensor": "coffee",
            "seconds": seconds,
            "volume": 0.0,
            "weight": 0.0,
            "flow": flow_rate,
            "pressure": 1.0,
            "exit": {"type": "pressure", "condition": "over", "value": stop_pressure},
        }

    steps = []
    if first_len > 0:
        steps.append(frame(boost_name, temps[0], first_len))
    if second_len > 0:
        steps.append(frame("preinfusion", temps[1], second_len))
    return steps


def _empty_step():
    """de1app's fallback when every duration is zero."""
    return {
        "name": "empty",
        "pump": "flow",
        "transition": "smooth",
        "temperature": 90.0,
        "sensor": "coffee",
        "seconds": 0.0,
        "volume": 0.0,
        "weight": 0.0,
        "flow": 0.0,
        "pressure": 0.0,
    }


def pressure_to_advanced_list(fields):
    """Derive frames for a settings_2a profile. Returns (steps, preinfuse_count)."""
    first_len, second_len, temps = _preinfusion_frame_lengths(fields)
    steps = _preinfusion_steps(
        fields, first_len, second_len, temps, "preinfusion temp boost"
    )
    preinfuse_count = len(steps)

    hold_time = _required_number(fields, "espresso_hold_time")
    decline_time = _required_number(fields, "espresso_decline_time")
    pressure = _required_number(fields, "espresso_pressure")
    maximum_flow = _optional_number(fields, "maximum_flow", 0.0)
    flow_range = _optional_number(
        fields, "maximum_flow_range_default", MAXIMUM_FLOW_RANGE_DEFAULT
    )

    def limited(step):
        if maximum_flow != 0:
            step["limiter"] = {"value": maximum_flow, "range": flow_range}
        return step

    def forced_rise(temperature):
        return {
            "name": "forced rise without limit",
            "pump": "pressure",
            "transition": "fast",
            "temperature": temperature,
            "sensor": "coffee",
            "seconds": 3.0,
            "volume": 0.0,
            "weight": 0.0,
            "flow": 0.0,
            "pressure": pressure,
        }

    if hold_time > 0:
        if hold_time > 3:
            steps.append(forced_rise(temps[2]))
            hold_time -= 3
        steps.append(
            limited(
                {
                    "name": "rise and hold",
                    "pump": "pressure",
                    "transition": "fast",
                    "temperature": temps[2],
                    "sensor": "coffee",
                    "seconds": hold_time,
                    "volume": 0.0,
                    "weight": 0.0,
                    "flow": 0.0,
                    "pressure": pressure,
                }
            )
        )

    if decline_time > 0:
        if hold_time < 3 and decline_time > 3:
            steps.append(forced_rise(temps[3]))
            decline_time -= 3
        steps.append(
            limited(
                {
                    "name": "decline",
                    "pump": "pressure",
                    "transition": "smooth",
                    "temperature": temps[3],
                    "sensor": "coffee",
                    "seconds": decline_time,
                    "volume": 0.0,
                    "weight": 0.0,
                    "flow": 0.0,
                    "pressure": _required_number(fields, "pressure_end"),
                }
            )
        )

    if not steps:
        steps.append(_empty_step())

    return steps, preinfuse_count


def flow_to_advanced_list(fields):
    """Derive frames for a settings_2b profile. Returns (steps, preinfuse_count)."""
    first_len, second_len, temps = _preinfusion_frame_lengths(fields)
    steps = _preinfusion_steps(
        fields, first_len, second_len, temps, "preinfusion boost"
    )
    preinfuse_count = len(steps)

    hold_time = _required_number(fields, "espresso_hold_time")
    maximum_pressure = _optional_number(fields, "maximum_pressure", 0.0)
    pressure_range = _optional_number(
        fields, "maximum_pressure_range_default", MAXIMUM_PRESSURE_RANGE_DEFAULT
    )

    def limited(step):
        if maximum_pressure != 0:
            step["limiter"] = {"value": maximum_pressure, "range": pressure_range}
        return step

    # de1app gates the decline frame on espresso_hold_time, not espresso_decline_time.
    # Reproduced deliberately; see doc/AI_STORAGE_NOTES.md.
    if hold_time > 0:
        steps.append(
            limited(
                {
                    "name": "hold",
                    "pump": "flow",
                    "transition": "fast",
                    "temperature": temps[2],
                    "sensor": "coffee",
                    "seconds": hold_time,
                    "volume": 0.0,
                    "weight": 0.0,
                    "flow": _required_number(fields, "flow_profile_hold"),
                    "pressure": 0.0,
                }
            )
        )
        steps.append(
            limited(
                {
                    "name": "decline",
                    "pump": "flow",
                    "transition": "smooth",
                    "temperature": temps[3],
                    "sensor": "coffee",
                    "seconds": _required_number(fields, "espresso_decline_time"),
                    "volume": 0.0,
                    "weight": 0.0,
                    "flow": _required_number(fields, "flow_profile_decline"),
                    "pressure": 0.0,
                }
            )
        )

    if not steps:
        steps.append(_empty_step())

    return steps, preinfuse_count


# ---------------------------------------------------------------------------
# TCL parser
# ---------------------------------------------------------------------------

def parse_tcl_profile(content):
    """Parse a de1app TCL profile into a dict matching v2 JSON structure.

    TCL profiles have two parts:
    1. advanced_shot - a TCL list of step dicts (may be empty for legacy profiles)
    2. Flat key-value pairs for profile metadata and legacy settings

    Returns a dict that can be fed into convert_profile().
    """
    result = {}

    # Extract advanced_shot first (it's a TCL nested list on one line)
    advanced_match = re.match(r'^advanced_shot\s+(.*)', content, re.MULTILINE)
    raw_steps_str = ""
    if advanced_match:
        raw_steps_str = advanced_match.group(1).strip()

    # Parse flat key-value pairs (everything except advanced_shot)
    for line in content.splitlines():
        line = line.strip()
        if not line or line.startswith("advanced_shot"):
            continue
        # TCL format: key value (value may be in {braces} for multi-word)
        match = re.match(r'^(\S+)\s+(.*)', line)
        if match:
            key = match.group(1)
            val = match.group(2).strip()
            # Remove TCL braces from values
            if val.startswith("{") and val.endswith("}"):
                val = val[1:-1]
            result[key] = val

    settings_type = result.get("settings_profile_type", "")

    # Map TCL field names to our expected names
    profile = {
        "title": result.get("profile_title", ""),
        "author": result.get("author", ""),
        "notes": result.get("profile_notes", ""),
        "beverage_type": result.get("beverage_type", "espresso"),
        "version": "2",
        "tank_desired_water_temperature": float(
            result.get("tank_desired_water_temperature", 0)
        ),
        "type": EDITOR_TYPE_BY_SETTINGS_TYPE.get(settings_type, "advanced"),
        "legacy_profile_type": settings_type,
    }

    if settings_type in LEGACY_TYPES:
        # de1app never reads the stored advanced_shot back for these types — it
        # regenerates from the scalars at load time. The stored array is whatever
        # was in the global ::settings when the file was last saved, so it is
        # ignored here whether it is empty or populated.
        if settings_type == LEGACY_PRESSURE_TYPE:
            steps, preinfuse_frames = pressure_to_advanced_list(result)
        else:
            steps, preinfuse_frames = flow_to_advanced_list(result)

        # The plain fields are authoritative for these types: the generators
        # overwrite the _advanced spellings from them, and de1app's stop switches
        # (de1plus/device_scale.tcl, de1plus/de1_de1.tcl) read them for anything
        # that is not settings_2c.
        profile["target_weight"] = _required_number(result, "final_desired_shot_weight")
        profile["target_volume"] = _required_number(result, "final_desired_shot_volume")
    else:
        steps = _parse_tcl_steps(raw_steps_str)
        if not steps and raw_steps_str not in ("", "{}"):
            raise ValueError("Failed to parse advanced_shot steps")
        preinfuse_frames = int(
            result.get("final_desired_shot_volume_advanced_count_start", 0)
        )
        profile["target_weight"] = float(
            result.get("final_desired_shot_weight_advanced", 0)
        )
        profile["target_volume"] = float(
            result.get("final_desired_shot_volume_advanced", 0)
        )

    profile["number_of_preinfuse_frames"] = preinfuse_frames
    profile["steps"] = steps
    return profile


def _parse_tcl_steps(raw):
    """Parse TCL advanced_shot list into a list of step dicts.

    The format is: {{key val key val ...} {key val key val ...} ...}
    Steps are delimited by {braces} inside the outer braces.
    """
    raw = raw.strip()
    if not raw or raw == "{}":
        return []

    # Remove outer braces
    if raw.startswith("{") and raw.endswith("}"):
        raw = raw[1:-1].strip()

    steps = []
    # Split on }{ boundaries (each step is in {braces})
    # But step values can contain {braces} too (e.g. name {Extraction start})
    step_strings = _split_tcl_list(raw)

    for step_str in step_strings:
        step = _parse_tcl_step(step_str)
        if step:
            steps.append(step)

    return steps


def _split_tcl_list(raw):
    """Split a TCL list into its top-level elements.

    Handles nested {braces} correctly.
    """
    elements = []
    depth = 0
    current = []
    i = 0

    while i < len(raw):
        ch = raw[i]
        if ch == "{":
            if depth == 0:
                current = []
            else:
                current.append(ch)
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                elements.append("".join(current))
            else:
                current.append(ch)
        else:
            if depth > 0:
                current.append(ch)
        i += 1

    return elements


def _parse_tcl_step(step_str):
    """Parse a single TCL step string into a profile step dict.

    TCL step format: key1 val1 key2 val2 ...
    Values can be in {braces} if they contain spaces.
    """
    tokens = _tokenize_tcl(step_str.strip())
    if len(tokens) < 2:
        return None

    raw = {}
    i = 0
    while i < len(tokens) - 1:
        key = tokens[i]
        val = tokens[i + 1]
        raw[key] = val
        i += 2

    # Map TCL step fields to our JSON step format
    step = {
        "name": raw.get("name", ""),
        "pump": raw.get("pump", "pressure"),
        "transition": raw.get("transition", "fast"),
        "temperature": float(raw.get("temperature", 0)),
        "sensor": raw.get("sensor", "coffee"),
        "seconds": float(raw.get("seconds", 0)),
        "volume": float(raw.get("volume", 0)),
        "weight": float(raw.get("weight", 0)),
        "flow": float(raw.get("flow", 0)),
        "pressure": float(raw.get("pressure", 0)),
    }

    # Build exit condition from TCL's split fields
    exit_if = int(raw.get("exit_if", 0))
    if exit_if:
        exit_type = raw.get("exit_type", "")
        if exit_type == "pressure_over":
            step["exit"] = {
                "type": "pressure",
                "condition": "over",
                "value": float(raw.get("exit_pressure_over", 0)),
            }
        elif exit_type == "pressure_under":
            step["exit"] = {
                "type": "pressure",
                "condition": "under",
                "value": float(raw.get("exit_pressure_under", 0)),
            }
        elif exit_type == "flow_over":
            step["exit"] = {
                "type": "flow",
                "condition": "over",
                "value": float(raw.get("exit_flow_over", 0)),
            }
        elif exit_type == "flow_under":
            step["exit"] = {
                "type": "flow",
                "condition": "under",
                "value": float(raw.get("exit_flow_under", 0)),
            }

    # Limiter (max_flow_or_pressure)
    max_val = float(raw.get("max_flow_or_pressure", 0))
    max_range = float(raw.get("max_flow_or_pressure_range", 0))
    if max_val > 0 or max_range > 0:
        step["limiter"] = {
            "value": max_val,
            "range": max_range,
        }

    return step


def _tokenize_tcl(s):
    """Tokenize a TCL key-value string, handling {braced} values."""
    tokens = []
    i = 0
    while i < len(s):
        # Skip whitespace
        while i < len(s) and s[i] in " \t":
            i += 1
        if i >= len(s):
            break

        if s[i] == "{":
            # Braced value — find matching close brace
            depth = 1
            i += 1
            start = i
            while i < len(s) and depth > 0:
                if s[i] == "{":
                    depth += 1
                elif s[i] == "}":
                    depth -= 1
                i += 1
            tokens.append(s[start : i - 1])
        elif s[i] == '"':
            # Quoted value
            i += 1
            start = i
            while i < len(s) and s[i] != '"':
                i += 1
            tokens.append(s[start:i])
            i += 1
        else:
            # Bare word
            start = i
            while i < len(s) and s[i] not in " \t":
                i += 1
            tokens.append(s[start:i])

    return tokens


# ---------------------------------------------------------------------------
# JSON/common conversion
# ---------------------------------------------------------------------------

def convert_step(step):
    """Convert a parsed profile step to Decent format."""
    converted = {
        "name": step["name"],
        "pump": step["pump"],
        "transition": step["transition"],
        "temperature": str(float(step["temperature"])),
        "sensor": step["sensor"],
        "seconds": str(float(step["seconds"])),
        "volume": str(float(step.get("volume", 0))),
        "weight": str(float(step.get("weight", 0))),
    }

    # Add flow or pressure based on pump type
    if step["pump"] == "flow":
        converted["flow"] = str(float(step.get("flow", 0)))
    else:
        converted["pressure"] = str(float(step.get("pressure", 0)))

    # Preserve the other target value too (our format includes both)
    if step["pump"] == "flow":
        converted["pressure"] = str(float(step.get("pressure", 0)))
    else:
        converted["flow"] = str(float(step.get("flow", 0)))

    # Exit condition
    if "exit" in step and step["exit"]:
        exit_cond = step["exit"]
        converted["exit"] = {
            "type": exit_cond["type"],
            "condition": exit_cond["condition"],
            "value": str(float(exit_cond["value"])),
        }

    # Limiter
    if "limiter" in step and step["limiter"]:
        limiter = step["limiter"]
        lim_value = float(limiter.get("value", 0))
        lim_range = float(limiter.get("range", 0))
        converted["limiter"] = {
            "value": str(lim_value),
            "range": str(lim_range),
        }

    return converted


def convert_profile(source):
    """Convert a parsed profile dict to Decent format."""
    # Resolve beverage type
    beverage_type = strip_tcl_braces(source.get("beverage_type", "espresso"))
    beverage_type = BEVERAGE_TYPE_MAP.get(beverage_type, beverage_type)
    if beverage_type not in VALID_BEVERAGE_TYPES:
        raise ValueError(
            f"Unknown beverage_type '{beverage_type}' "
            f"(original: '{source.get('beverage_type')}')"
        )

    # Resolve tank temperature (de1app uses 'tank_desired_water_temperature')
    tank_temp = source.get(
        "tank_temperature",
        source.get("tank_desired_water_temperature", 0),
    )

    # Resolve target_volume_count_start (de1app uses 'number_of_preinfuse_frames')
    vol_count_start = source.get(
        "target_volume_count_start",
        source.get("number_of_preinfuse_frames", 0),
    )

    # Convert steps
    steps = [convert_step(s) for s in source.get("steps", [])]

    converted = {
        "version": str(source.get("version", "2")),
        "title": source.get("title", ""),
        "author": source.get("author", ""),
        "notes": source.get("notes", ""),
        "beverage_type": beverage_type,
        "steps": steps,
        "tank_temperature": str(float(tank_temp)),
        "target_weight": str(float(source.get("target_weight", 0))),
        "target_volume": str(float(source.get("target_volume", 0))),
        "target_volume_count_start": str(int(vol_count_start)),
        "type": source.get("type", "advanced"),
        "hidden": "0",
    }

    return converted


def load_profile(input_path):
    """Load a profile from JSON or TCL file, returning a parsed dict."""
    with open(input_path) as f:
        content = f.read()

    if input_path.endswith(".tcl"):
        return parse_tcl_profile(content)
    else:
        return json.loads(content)


# ---------------------------------------------------------------------------
# Source resolution and provenance
# ---------------------------------------------------------------------------

PROFILE_EXTENSIONS = (".tcl", ".json")

# Directories under a de1app `de1plus/` root that hold ingestible profiles.
# de1app ships stale copies of four A-Flow profiles in `profiles/` that shadow the
# plugin's newer ones (de1app issue #350), so all three are scanned and disagreements
# are reported rather than resolved.
SOURCE_DIR_GLOBS = (
    "profiles",
    "plugins/*/profiles",
    "profile_editors/*/profiles",
)


def _profile_files_in(directory):
    return sorted(
        os.path.join(directory, name)
        for name in os.listdir(directory)
        if name.endswith(PROFILE_EXTENSIONS)
    )


def source_dirs_under(root):
    """The profile directories a de1app `de1plus` root contributes, or none."""
    dirs = []
    for pattern in SOURCE_DIR_GLOBS:
        dirs.extend(
            sub
            for sub in sorted(glob.glob(os.path.join(root, pattern)))
            if os.path.isdir(sub)
        )
    return dirs


def expand_source_dir(path):
    """Expand a directory argument into the profile files it contributes.

    A de1app `de1plus` root contributes its base, plugin and profile-editor profile
    directories. Any other directory contributes its own profile files.
    """
    source_dirs = source_dirs_under(path)
    if not source_dirs:
        return _profile_files_in(path)

    files = []
    for directory in source_dirs:
        files.extend(_profile_files_in(directory))
    return files


def resolve_inputs(paths):
    """Turn the positional arguments into a de-duplicated list of profile files."""
    resolved = []
    for path in paths:
        if os.path.isdir(path):
            resolved.extend(expand_source_dir(path))
        else:
            resolved.append(path)

    seen = set()
    unique = []
    for path in resolved:
        key = os.path.realpath(path)
        if key not in seen:
            seen.add(key)
            unique.append(path)
    return unique


def source_provenance(input_path):
    """Describe where a profile came from: repo-relative path plus commit.

    `git -C` inside a submodule reports the submodule's own HEAD, which is what a
    plugin profile's provenance should name.
    """
    directory = os.path.dirname(os.path.abspath(input_path)) or "."

    def git(*args):
        try:
            out = subprocess.run(
                ["git", "-C", directory, *args],
                capture_output=True,
                text=True,
                check=True,
            )
        except (subprocess.CalledProcessError, FileNotFoundError):
            return None
        return out.stdout.strip()

    top = git("rev-parse", "--show-toplevel")
    revision = git("rev-parse", "HEAD")

    if top:
        source = os.path.relpath(os.path.abspath(input_path), top)
        origin = git("remote", "get-url", "origin")
    else:
        source = os.path.abspath(input_path)
        origin = None

    provenance = {"source": source}
    if origin:
        provenance["repository"] = origin
    if revision:
        provenance["revision"] = revision
    return provenance


def find_collisions(converted_by_output):
    """Report output filenames claimed by more than one disagreeing source.

    Identical copies in two directories are not an error — de1app's plugin and
    profile_editor submodules are the same upstream repo at the same commit, so a
    profile legitimately appears twice.
    """
    collisions = {}
    for out_filename, entries in converted_by_output.items():
        distinct = {json.dumps(c, sort_keys=True) for _, c in entries}
        if len(distinct) > 1:
            collisions[out_filename] = [path for path, _ in entries]
    return collisions


def load_manifest(output_dir):
    manifest_path = os.path.join(output_dir, "manifest.json")
    if os.path.exists(manifest_path):
        with open(manifest_path) as f:
            return json.load(f)
    return {
        "version": "1.0.0",
        "description": "Default espresso profiles bundled with Decent",
        "profiles": [],
    }


def write_manifest(output_dir, manifest):
    with open(os.path.join(output_dir, "manifest.json"), "w") as f:
        json.dump(manifest, f, indent=2)
        f.write("\n")


def update_manifest(output_dir, new_filenames, provenance_by_filename=None):
    """Add new filenames to manifest.json and record where each one came from."""
    manifest = load_manifest(output_dir)

    existing = set(manifest["profiles"])
    added = []
    for name in new_filenames:
        if name not in existing:
            manifest["profiles"].append(name)
            added.append(name)

    manifest["profiles"].sort()

    if provenance_by_filename:
        provenance = manifest.get("provenance", {})
        provenance.update(provenance_by_filename)
        manifest["provenance"] = dict(sorted(provenance.items()))

    write_manifest(output_dir, manifest)

    return added


def output_filename_for(input_path):
    filename = os.path.basename(input_path)
    if filename.endswith(".tcl"):
        return filename.rsplit(".", 1)[0] + ".json"
    return filename


def main_with_args(argv=None):
    parser = argparse.ArgumentParser(
        description="Ingest de1app TCL or v2 JSON profiles into Decent format"
    )
    parser.add_argument(
        "profiles",
        nargs="+",
        help="Input profile files (.json or .tcl), or directories to scan. A de1app "
        "de1plus/ root also contributes plugins/*/profiles and "
        "profile_editors/*/profiles.",
    )
    parser.add_argument("-o", "--output-dir", help="Output directory for converted profiles")
    parser.add_argument("--dry-run", action="store_true", help="Print to stdout instead of writing")
    parser.add_argument("--update-manifest", action="store_true", help="Update manifest.json")

    args = parser.parse_args(argv)

    inputs = resolve_inputs(args.profiles)

    # Convert everything before writing anything, so a source collision is caught
    # while it can still stop the output file being produced.
    converted_by_output = {}
    errors = []
    for input_path in inputs:
        try:
            converted = convert_profile(load_profile(input_path))
        except Exception as e:
            errors.append((os.path.basename(input_path), str(e)))
            print(f"FAIL  {os.path.basename(input_path)}: {e}", file=sys.stderr)
            continue
        converted_by_output.setdefault(output_filename_for(input_path), []).append(
            (input_path, converted)
        )

    collisions = find_collisions(converted_by_output)
    for out_filename, paths in collisions.items():
        del converted_by_output[out_filename]
        detail = "\n".join(f"      {p}" for p in paths)
        message = f"same profile in {len(paths)} source directories, and they disagree:\n{detail}"
        errors.append((out_filename, message))
        print(f"FAIL  {out_filename}: {message}", file=sys.stderr)

    converted_filenames = []
    provenance_by_filename = {}

    for out_filename, entries in converted_by_output.items():
        input_path, converted = entries[0]
        filename = os.path.basename(input_path)

        if args.dry_run:
            print(f"=== {filename} -> {out_filename} ===")
            print(json.dumps(converted, indent=2))
            print()
        elif args.output_dir:
            output_path = os.path.join(args.output_dir, out_filename)
            with open(output_path, "w") as f:
                json.dump(converted, f, indent=2)
                f.write("\n")
            print(f"  OK  {filename} -> {output_path}")
            converted_filenames.append(out_filename)
            provenance_by_filename[out_filename] = source_provenance(input_path)
        else:
            print(json.dumps(converted, indent=2))

    if args.update_manifest and args.output_dir and converted_filenames:
        added = update_manifest(
            args.output_dir, converted_filenames, provenance_by_filename
        )
        if added:
            print(f"\nAdded {len(added)} profiles to manifest.json")
        else:
            print("\nNo new profiles added to manifest (all already present)")
        print(f"Recorded provenance for {len(provenance_by_filename)} profiles")

    if errors:
        print(f"\n{len(errors)} error(s):", file=sys.stderr)
        for name, err in errors:
            print(f"  {name}: {err}", file=sys.stderr)
        return 1

    print(f"\nConverted {len(converted_filenames)} profiles successfully")
    return 0


if __name__ == "__main__":
    sys.exit(main_with_args())
