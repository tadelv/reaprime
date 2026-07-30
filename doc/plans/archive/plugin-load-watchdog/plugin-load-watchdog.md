# Plugin load watchdog plan

## Problem

Plugin auto-load runs off the boot critical path, but a plugin that throws or never completes loading is retried on every launch. The existing `Future.any` timeout does not persist failures and cannot protect the next launch if synchronous JavaScript evaluation stalls the process.

## Acceptance criteria

- When a plugin load fails, Decent.app records one consecutive failure without failing initialization of other plugins.
- When a plugin reaches three consecutive load failures, Decent.app disables its auto-load setting.
- When a plugin loads successfully, Decent.app clears its consecutive failure count.
- When the previous process ended during a plugin load, the next launch disables that plugin before auto-loading plugins.
- When a user re-enables auto-load, Decent.app clears the watchdog state so the plugin gets a fresh attempt.
- Plugin load attempts remain bounded by the existing one-second limit where the JavaScript runtime yields to Dart.

## Implementation

1. Add persistent SharedPreferences keys for the current load and per-plugin failure count.
2. Wrap `PluginManager.loadPlugin` with `Future.timeout`; set/clear the current-load marker around it and update failure state on error.
3. Recover a stale current-load marker during initialization before auto-load begins.
4. Add focused service tests and document the lifecycle behavior in `doc/Plugins.md`.

## Scope boundary

No new plugin health-check callback, settings screen, API field, dependency, or JavaScript-runtime isolation. The existing settings and REST enable controls remain the re-enable path.
