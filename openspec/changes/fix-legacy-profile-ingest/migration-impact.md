# Migration impact

Covers task 3b.6 (what the profile-hash change invalidates) and task 6.1 (design open
question 1 - do corrected profiles reach users who already hold a copy).

## What the hash change touches

`ProfileHash.calculateProfileHash` includes `beverage_type`, so the 15 retyped profiles
get a new id, as do the 11 whose frames or targets change. **26** of the 70 previously
bundled profiles change id; `A-Flow____default-light.json` is the 71st and is an
addition, so it has no prior id and no user can have hidden it.

Nothing references a profile id from outside the profile store:

- No foreign key anywhere. A repo-wide search for `profileId` finds nothing; no Drift
  table and no SharedPreferences key holds one.
- `Workflow` embeds the whole `Profile` **by value** (`workflow.dart:10`), and shots
  record the workflow. Historical shots keep the profile they were pulled with, and
  are unaffected by the bundled copy changing.
- The only id consumers are `ProfileController` and the profile storage service.

So the blast radius is the profile store alone.

## Do corrected profiles reach existing users? Yes, and the mechanism already exists

`ProfileController._loadDefaultProfilesIfNeeded` runs on every launch. For a bundled
profile whose content changed:

1. The new content hashes to a new id, is not found in storage, and is stored.
2. `_retireStaleDefaults` finds the old record via its seeded `metadata.filename`, sees
   `currentIdByFilename[filename] != record.id`, and **hides** it - never deletes it.

Corrected profiles therefore reach existing installs without any new migration code.

## "Whether the local copy tracks modification" - it cannot be modified

The design's recommendation was to *replace where the local copy is unmodified, leave
and notify where it is not*, noting the answer depends on whether modification is
tracked. It is not tracked, because the state cannot arise:

`ProfileController.update` rejects it outright (`profile_controller.dart:272`):

```dart
if (existing.isDefault && profile != null) {
  throw ArgumentError('Cannot modify default profile content');
}
```

A user who wants a variant of a bundled profile creates a **new** profile. That record
has `isDefault: false`, its own content hash, and optionally a `parentId` for lineage.
`_retireStaleDefaults` skips it on the first line of its loop (`!record.isDefault`), so
a user's derivative is never touched by this change. It keeps the old frames, which is
correct - it is their profile now, not a stale bundled default.

**Conclusion for open question 1:** no decision is needed and no new mechanism is
warranted. The two cases the question worried about - unmodified bundled copy, and
user-modified copy - are already handled correctly and differently by existing code.

## One real consequence, worth deciding on separately

A user who **hid** a bundled default will see the corrected version reappear, visible.

`_retireStaleDefaults` hides the record whose id no longer matches, but it only
considers records that are currently visible (`record.visibility != Visibility.visible`
-> `continue`), and the corrected content arrives as a *new* record created by
`ProfileRecord.create`, which hard-codes `visibility: Visibility.visible`
(`profile_record.dart:116`). The old hidden record stays hidden; the new one shows up.

This affects the 26 changed profiles, not only the retyped ones, and it is not new
behaviour introduced here - any corpus change has always done this. It is simply
reaching 27 profiles at once for the first time.

The honest framing for the frame/target corrections is that the current content is a
defect rather than a choice - a `Default` brewing at 54 C, a `Classic Italian espresso`
stopping at 60 g instead of 36 g. Surfacing the corrected version is arguably right.
For the 15 beverage-type-only corrections it is harder to justify: a user who hid
`Tea portafilter/oolong` gets it back because its label changed from `pourover` to
`tea_portafilter`, with the shot itself untouched.

Options, if this is judged worth fixing:

1. Leave it. Simplest; a user re-hides 27 profiles once.
2. Carry visibility forward in `_loadDefaultProfilesIfNeeded`: when a stored default
   with the same `metadata.filename` is being superseded, seed the replacement with the
   old record's visibility. Small and contained, and it makes every future corpus
   correction respect the user's hiding.

Option 2 is the better behaviour and is a handful of lines, but it changes seeding
semantics for all bundled profiles, so it is outside this change's scope and is called
out here rather than done silently.
