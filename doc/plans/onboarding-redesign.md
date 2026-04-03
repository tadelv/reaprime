# Onboarding Redesign — Tracking Document

Branch: `feature/onboarding`

## Agreed Design Decisions

### Flow Order
1. **Welcome** (NEW) — light explainer, one screen, "Get Started" button
2. **Permissions** (existing) — auto-advances, self-skips if already granted
3. **Initialization** (existing) — auto-advances
4. **Import Data** (NEW) — file-picker based, skip available
5. **Scan / Connect** (existing) — device discovery and connection

### Onboarding Flag
- New `onboardingCompleted` preference flag
- Set to `true` when user passes Import step (whether they imported or skipped)
- Controls visibility of Welcome and Import steps only
- Permissions, Init, and Scan always run regardless of flag

### Welcome Step
- Light explainer: what the app does + hint about import coming next
- Single screen with "Get Started" button
- Content reused in an About dialog elsewhere in the app
- App name: "Streamline Bridge" (abbreviate to "Bridge" where needed)
- Copy:
  > **Welcome to Streamline Bridge**
  >
  > Control your Decent espresso machine, manage profiles, and track your shots — right here or from any device on your network.
  >
  > Coming from the Decent app? You can import your data next.

### Import Step
- Unified file-picker UI on all platforms (no auto-detect, no MANAGE_EXTERNAL_STORAGE)
- Two import source options:
  - Import from Decent app — user picks de1plus folder via file picker
  - Import Streamline/Bridge.app backup — user picks .zip file via file picker
- "Skip for now" option
- Determinate progress bar with item counts (requires pre-scan phase)
- Errors: continue through failures, show summary at end
- Error summary has expandable details + share/report button
- Import functionality reused in Settings > Data Management

#### De1app Folder Import — Internals
- **Data sources (priority order):**
  1. `history_v2/*.json` — preferred, self-contained JSON shot files
  2. `history/*.shot` — fallback, TCL format (Visualizer repo has reference parser)
  3. `profiles_v2/*.json` — standalone profiles not found embedded in shots
  4. `plugins/DYE/grinders.tdb` — DYE grinder specs (TCL format)
  5. `plugins/SDB/shots.db` — SKIP (redundant, all data comes from shot files)
- **Entity extraction:** Full deduplication and entity creation:
  - Beans: deduplicate by (brand + type), create Bean + BeanBatch records
  - Grinders: deduplicate by (model), merge with DYE grinder specs if available
  - Profiles: deduplicate by content hash (existing mechanism)
  - Shots: create ShotRecord with WorkflowContext linked to created entity IDs
- **Import flow:**
  1. Pre-scan — count files, detect available data sources
  2. Summary screen — show counts (shots, profiles, coffees, grinders), "Import All" button
  3. Import with determinate progress bar + item counts
  4. Completion summary — imported counts, errors with expandable details + share/report
- **No selective import** — "Import All" only, deduplication/skip handles conflicts
- **Reference for TCL parsing:** Visualizer project (github.com/miharekar/visualizer) `app/models/parsers/decent_tcl.rb`
- **Shot v2 JSON structure:** `{timestamp, elapsed, pressure, flow, temperature, totals, profile, meta, app}` — profile and DYE metadata embedded in `app.data.settings`

### Settings > Data Management
- Add "Import from Decent app" option alongside existing "Import Streamline backup"
- Reuses same import widgets/flow from onboarding (folder picker → pre-scan → summary → progress → result)
- Conflict handling: skip duplicates silently, report skipped count in result summary
- No "Skip for now" option (user explicitly chose to import)
- Layout: Export section, Import section (two options), Logs section

### Error Report Detail View
- Expandable error list: filename + one-line error reason per failed item
- "Share Report" button generates a plain text file containing:
  - App version / platform
  - Import source type
  - Total counts (imported, skipped, errors per category)
  - Full error details per file (more verbose than UI)
  - App log file contents appended
- Shared via platform share sheet (mobile) or file picker save (desktop)
- No integration with feedback/GitHub issue system — just a file

### What We're NOT Doing
- No auto-detection of de1app folder
- No multi-page walkthrough on welcome
- No re-trigger onboarding option
- No nagging on subsequent launches if import was skipped

## Items to Brainstorm

- [x] **Welcome screen copy** — finalized (see above)
- [x] **Import step internals** — finalized (see above)
- [x] **Settings import UX** — finalized (see below)
- [x] **Error report detail view** — finalized (see below)

## Implementation Status

- [ ] Write spec/plan from finalized design
- [ ] Welcome step widget
- [ ] Onboarding flag in preferences
- [ ] Import step UI (picker, progress, summary)
- [ ] Shot v2 JSON parser (history_v2/)
- [ ] TCL shot parser (history/)
- [ ] Profile v2 JSON importer (profiles_v2/)
- [ ] DYE grinders.tdb parser
- [ ] Bean/Grinder entity extraction and deduplication
- [ ] Pre-scan / count phase
- [ ] Error summary + report view
- [ ] Settings > Data Management improvements
- [ ] About dialog with welcome content
- [ ] Tests
