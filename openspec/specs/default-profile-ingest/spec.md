# default-profile-ingest Specification

## Purpose

Correctness and provenance of the bundled default profile corpus in
`assets/defaultProfiles/`: which de1app source directory each profile is harvested
from, how legacy `settings_2a`/`2b` profiles have their frames derived rather than
copied, and the guards that stop a future harvest silently reintroducing stale or
shadowed content.

The corpus is built by `tools/ingest_profiles.py`. Operational detail — the de1app
quirks reproduced deliberately, why A-Flow comes from the plugin directory, and why the
rebuild is a scoped allowlist rather than a full re-ingest — lives in
`doc/AI_STORAGE_NOTES.md`.
## Requirements
### Requirement: Legacy profile frames are derived, never copied

For a de1app profile of type `settings_2a` or `settings_2b`, the ingest tool SHALL derive the frame list from the profile's scalar fields and SHALL NOT use the `advanced_shot` array, whether that array is empty or populated. de1app itself does not read that array back for these types — it regenerates at load time — and because `save_profile` writes it from the global `::settings`, a populated array routinely describes a different profile entirely.

Where derivation is not possible, the tool SHALL fail with a named error rather than emit a profile carrying copied frames.

#### Scenario: A legacy profile with a populated stale array is not copied

- **WHEN** the tool ingests a `settings_2a` profile whose `advanced_shot` is populated
- **THEN** the stored array is ignored and the frames are derived from the profile's scalars
- **AND** the output does not contain any frame taken from that array

#### Scenario: A legacy profile with an empty array is still ingestible

- **WHEN** the tool ingests a `settings_2b` profile whose `advanced_shot` is empty
- **THEN** the frames are derived from the profile's scalars and the profile is emitted
- **AND** the tool does not reject it

#### Scenario: Advanced profiles keep their stored frames

- **WHEN** the tool ingests a profile of type `settings_2c`
- **THEN** the stored `advanced_shot` frames are used as-is, because for that type they are authoritative

### Requirement: Stop targets are resolved by profile type

Where de1app carries two spellings of the same field, the ingest tool SHALL resolve which is authoritative from `settings_profile_type`, matching de1app's own runtime behaviour. For the shot stop targets that means `final_desired_shot_weight` / `final_desired_shot_volume` for `settings_2a` and `settings_2b`, and the `_advanced` spellings only for `settings_2c`.

This is not a stylistic choice about which key to prefer — it is the switch de1app evaluates when deciding to stop the shot (`de1plus/device_scale.tcl` for weight, `de1plus/de1_de1.tcl` for volume). Reading the `_advanced` spelling unconditionally makes `Classic Italian espresso` stop at 60 g where de1app stops at 36 g, and removes the stop entirely from two others.

#### Scenario: A legacy profile takes the plain target

- **WHEN** the tool ingests a `settings_2a` or `settings_2b` profile
- **THEN** the emitted target weight and volume come from `final_desired_shot_weight` / `final_desired_shot_volume`
- **AND** the `_advanced` spellings are not consulted

#### Scenario: An advanced profile takes the advanced target

- **WHEN** the tool ingests a `settings_2c` profile
- **THEN** the emitted target weight and volume come from the `_advanced` spellings

#### Scenario: Editor type reflects the source type

- **WHEN** a profile is typed `settings_2a` or `settings_2b` in de1app
- **THEN** the emitted profile is not labelled `advanced`

### Requirement: Derived frames agree with the profile's own scalars

A bundled profile of type `settings_2a`/`2b` SHALL NOT ship frames that contradict its own scalar fields. At minimum, no frame's temperature may differ from the profile's declared brew temperature except where the derivation itself introduces the difference.

This is the check that would have caught `Default` shipping 75 °C and 54 °C frames against a declared `espresso_temperature` of 90.0.

#### Scenario: A contradicting bundled profile fails the suite

- **WHEN** the test suite runs against `assets/defaultProfiles/`
- **THEN** any legacy-type profile whose frames contradict its scalars fails the suite
- **AND** the failure names the profile and the contradicting field

### Requirement: Beverage type is preserved, not flattened

The ingest tool SHALL carry de1app's beverage type through unchanged, and the app SHALL accept `tea`, `tea_portafilter` and `filter` as distinct values rather than mapping them onto `pourover`. The serialised spelling SHALL match de1app's exactly, including the underscore in `tea_portafilter`.

Adding vocabulary SHALL NOT add behaviour: the scaleless handling reserved for `cleaning` and `calibrate` does not extend to the new values.

#### Scenario: A tea profile keeps its type

- **WHEN** a de1app profile declares `beverage_type tea_portafilter`
- **THEN** the ingested profile carries `tea_portafilter`, not `pourover`
- **AND** it parses back to the tea-portafilter value rather than falling back to espresso

#### Scenario: The wire spelling round-trips

- **WHEN** a profile carrying `tea_portafilter` is parsed and re-serialised
- **THEN** the output spelling is `tea_portafilter`

#### Scenario: Tea profiles still require a scale

- **WHEN** a profile of a newly-accepted beverage type is brewed
- **THEN** it is treated like espresso and pour-over, not like cleaning or calibrate

### Requirement: Profile source directory is explicit and collision-safe

The tool SHALL treat a profile present in more than one de1app source directory as an error when the copies differ, reporting every path involved rather than selecting one. Plugin and profile-editor directories (for example `de1plus/plugins/A_Flow/profiles/`) SHALL be usable as ingest sources.

de1app ships stale copies of four A-Flow profiles in `de1plus/profiles/` that permanently shadow the plugin's newer ones (de1app issue #350). Selecting silently — by directory order or by first-seen — is what put 6-frame copies in the corpus while a 9-frame source sat in the same checkout.

#### Scenario: Disagreeing copies are reported, not resolved

- **WHEN** the same profile title is found in both a base and a plugin directory, and the two produce different frames
- **THEN** the tool fails and names both source paths
- **AND** no output file is written for that profile

#### Scenario: Identical copies in two directories are not an error

- **WHEN** the same profile title is found in two directories and both produce identical output
- **THEN** the tool emits it once without error

### Requirement: The bundled corpus records where each profile came from

Each bundled default profile SHALL carry enough provenance to answer "which source produced this?" without re-deriving it — at minimum the de1app source path and the commit or release it was harvested from.

The corpus was assembled from Visualizer uploads and de1app copy-exports mixed together, and the absence of this record is why two corrupted profiles (`Default`, `Gentle and sweet`) could not be attributed without running the tool against every candidate source to see which one reproduced them.

#### Scenario: A profile's origin is answerable from the corpus

- **WHEN** a bundled profile's content is questioned
- **THEN** its recorded provenance identifies the source path and revision it was ingested from

