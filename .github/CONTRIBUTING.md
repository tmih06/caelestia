# Contributing

Caelestia is a Quickshell/Qt Quick desktop shell with native C++ QML modules.
Use this guide for changes to this repository, including work by coding agents.
Dependency installation and user configuration belong in the [README](../README.md).
Commands below run from the repository root unless stated otherwise.

## Safe workflow

1. **Find the owner.** Trace the affected surface through its wrapper, shared
   components, services, and native implementation. Use the code map below;
   inspect callers before changing an interface. Keep changes local to the task.
2. **Identify the runtime.** Run `qs list --all`. Match the configuration path,
   display, and instance ID to this checkout. Inspect IPC targets and logs using
   explicit instance selection, as shown below.
3. **Capture a baseline.** Reproduce the interaction or record resource usage
   before editing. Separate existing configuration warnings from new failures.
4. **Change and exercise.** QML edits may immediately reload the user's shell.
   Native changes require a rebuild and process restart. Verify the original
   scenario in the correct runtime, including closing and reopening the surface.
5. **Restore state.** Remove probes and test processes, restore any playback,
   drawer, or configuration state changed by verification, and report evidence.

Treat the session as user-owned. Do not unlock the desktop, restart a locked
shell, disconnect networking, change audio routing, or overwrite user settings
as a testing shortcut. Use silent test players or isolated fixtures when needed.
Before a required restart, check `lock isLocked`, target only the intended
instance, wait for its exit, then launch the replacement. Starting too early
with `-n` can report an existing instance and leave no replacement after it exits.

Preserve unrelated working-tree changes. Commit and push only when requested;
verify the intended remote and branch instead of assuming `origin` or a tracking
branch exists.

## Code map

| Area | Ownership / starting point |
| --- | --- |
| `shell.qml` | Startup, environment pragmas, root modules, eager singleton initialization. |
| `modules/drawers/` | Actual drawer host, input regions, backgrounds, panel composition. |
| `modules/dashboard/` | Compact dock, shared media morph, translated page layout, dashboard cards. |
| Other `modules/` directories | Bar, launcher, lock, notifications/sidebar, settings (`nexus`), clipboard, and other surfaces. |
| `components/` | Reusable controls, images, effects, containers, animation primitives. |
| `services/` | QML singletons for media, audio, networking, notifications, weather, and compositor state. |
| `daemons/` | Long-lived shortcuts, idle inhibition, battery and session behavior. |
| `plugin/src/Caelestia/` | Native rendering, audio DSP, resource services, models, image cache, settings, state, and translations. |
| `utils/`, `scripts/` | QML helpers and development/checking tools respectively. |
| `nix/`, `flake.nix`, `CMakeLists.txt` | Packaging, development environment, build/install entrypoints. |

`Config` and `Tokens` are screen-aware attached properties; `GlobalConfig` and
`TokenConfig` expose their global roots. Screen inheritance follows the item
tree; raw `QtObject` services do not inherit it as visual items do. Preserve
per-monitor behavior when moving a binding between a visual item and a singleton.
Use the existing token, palette, and animation abstractions rather than embedding
another set of sizes, colors, or easing curves.

`ShellState` owns per-screen drawer state and component references.
`PersistentState` and `RuntimeState` are native state roots, distinct from
configuration. Check the appropriate owner before adding state.

## Build and run

Install dependencies using the [manual installation instructions](../README.md#manual-installation),
or use the Nix development shell. `.envrc` documents the direnv build environment;
review it before allowing it, since entering that environment can build the plugin.

For a new local build directory:

```sh
cmake -S . -B build -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
cmake --build build --parallel 2
```

For an existing build, preserve its configuration and run the build command only.
Adjust parallelism to available memory. `build/` contains generated files and
native QML modules; edit their sources under `plugin/`, not generated output or
vendored `plugin/3rdparty/` code.

For local execution, the native imports and version helper must resolve to this
build:

```sh
export CAELESTIA_LIB_DIR="$PWD/build/lib"
export QML2_IMPORT_PATH="$PWD/build/qml${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}"
```

**Check `shell.qml` first:** this checkout currently sets `QML2_IMPORT_PATH` in an
`Env` pragma. That can override the inherited variable and point another checkout
at the wrong plugin. Verify that path before diagnosing missing modules or
claiming a native fix is loaded.

If this configuration is not already running, launch from the real Wayland
session:

```sh
qs -p "$PWD/shell.qml" -n -d
```

Source `shell.qml` enables file watching; the install step generates a version
with watching disabled. Ordinary shell QML loads from the checkout, while C++,
native shaders, and QML bundled inside native modules need rebuilding. C++ and
shader changes need a fresh shell process; a successful QML reload is not proof
that the rebuilt library is active.

### Inspecting the running shell

After `qs list --all`, set `INSTANCE` to the ID for this checkout:

```sh
qs ipc --id "$INSTANCE" show
qs log --id "$INSTANCE" --tail 80 --no-color
qs ipc --id "$INSTANCE" call lock isLocked
qs ipc --id "$INSTANCE" call drawers list
qs ipc --id "$INSTANCE" call mpris getActive isPlaying
```

Instance IDs, PIDs, and display names change. Without explicit selection,
Quickshell may look for a nonexistent `default` configuration or filter out a
shell on another display. Discovery commands work without changing desktop state.

Remote tools may lack the session's `WAYLAND_DISPLAY`, `XDG_RUNTIME_DIR`,
`HYPRLAND_INSTANCE_SIGNATURE`, or D-Bus environment. For display tools and smoke
processes, obtain only the required values from the intended shell process;
do not print its full environment or replace the agent's whole environment.
Keep the intended local native-import path explicit.

## Rendering and dashboard invariants

- **Natural size and viewport are different.** Dashboard pages retain their
  natural layout dimensions while the viewport animates. `Content.qml` translates
  pages; `Wrapper.qml` coordinates expansion with one `morph` value. Independent
  animations on shared child geometry cause delayed time labels and markers.
- **Cached is not active.** The media dock keeps expanded content loaded for
  morph targets. Use `contentActive` / `pageActive` and the existing gates for
  sensor references, timers, GIFs, lyric fetching, and spectrum updates.
  Parent opacity zero does not make a child's own `opacity` zero. Effective
  visibility, enabled state, and explicit activity are separate concerns.
- **Keep positioners measurable.** Using `visible: false` for cached pages can
  remove them from a `Row`'s layout and break page offsets and drawer sizing.
  Retain the existing opacity culling and explicit work gating.
- **Share media visuals.** `MediaDock.qml` owns the artwork, title, metadata,
  timeline, and time labels used by the compact/expanded morph. Target items in
  the expanded page supply geometry; adding a second rendered copy risks
  flicker and overlapping titles. Shared visuals follow the Media page offset
  and clip to its viewport during tab switching.
- **Preserve the animation contract.** Spatial motion uses `Anim` and its
  expressive curves. Test spring overshoot and interrupted transitions, not just
  final geometry. Keep the dock timebar flat, the expanded slider wavy, and the
  compact marker synchronized with the same morph. Waveform sampling continues
  through fade-out, then stops. Long titles scroll in both sizes.
- **Treat media capability as data.** `MediaProgress.qml` owns interpolation,
  seeks, and duration caching. Some MPRIS players report current position as
  length when duration is unsupported. Preserve unknown-duration elapsed time
  and the non-seekable state instead of inventing a total duration.
- **Give calendar delegates cell geometry.** Weekdays and dates use seven
  matching column widths and spacing. The six-row natural height comes from
  font metrics, not the assigned cell height; feeding assigned size back into
  implicit size causes layout failures.

## Resource lifecycle

Optimize measured work without removing visual features or reducing animation
fidelity as a substitute for fixing the cause.

- Gate a native `ServiceRef` with consumer activity. The first reference starts
  work and the last stops it; repeated activation must not accumulate connections,
  threads, processes, or database handles. Resource services refresh on activation.
- Keep hardware, filesystem, and subprocess work off frame callbacks. Reuse
  scratch buffers and cached geometry in hot paths. Qt containers are implicitly
  shared: publishing a scratch buffer can move allocation to the next write via
  copy-on-write. Keep mutable scratch separate from queued snapshots and bound
  in-flight updates.
- **Idle and shutdown are different.** `AudioCollector::stop()` joins its
  worker. Cancellation must wake the PipeWire loop explicitly, including while
  idle; relying on a periodic stop check can block the UI for that timer interval.
  A stop callback must finish before the loop it references is destroyed.
- Keep background refresh ownership in services. Widget creation should not
  duplicate a service's startup/hourly fetch. Passive NetworkManager list reads
  use cached data; explicit rescans are a separate operation. Preserve
  single-flight callbacks, event coalescing, and finished-process destruction.
- Allocate layers and captures for the effect that needs them. In
  `WallpaperImpl.qml`, interrupted changes capture the currently displayed blend;
  completion releases capture sources and the transition effect. Check both
  cases when changing texture ownership.
- Bound image decoding in device pixels, accounting for DPR. Clipboard previews
  use size buckets to avoid full-size decodes and per-frame resize reloads.
  Avoid changing image `sourceSize` on every morph frame.
- Close and remove named SQL connections after their queries/handles are gone.
  Exercise repeated model destruction or reloads; normal application exit alone
  will hide a session-long connection leak.

## Validation

### Static checks

Follow the commands and formatting policy in
[the CI workflow](workflows/check-format.yml). The paths below are examples;
substitute the files changed by your task.

```sh
python3 scripts/qml-lint-conventions.py --file modules/dashboard/Content.qml
python3 scripts/trs-check.py --file modules/dashboard/Content.qml
/usr/lib/qt6/bin/qmlformat modules/dashboard/Content.qml | diff -u modules/dashboard/Content.qml -
/usr/lib/qt6/bin/qmllint -I build/qml modules/dashboard/Content.qml
clang-format --dry-run --Werror plugin/src/Caelestia/Services/service.cpp
```

The Qt paths above are for Arch; use the equivalent Qt **6** tools elsewhere.
An unqualified `qmllint` can resolve to Qt 5. The `qs.*` imports are supplied by
Quickshell, so standalone Qt lint can report unresolved imports/types; distinguish
those limits from syntax errors and actual runtime warnings. A zero exit status
alone is not a clean static analysis result.

The convention checker enforces QML member/import ordering. Keep handlers and
functions in the expected sections; formatters alone do not establish correctness.
For user-facing strings, use `Caelestia.I18n`'s `Tr` helpers, extractable literals,
and chained `.arg()` substitutions; check changed strings with `trs-check.py`.
Limit formatting to the affected code.

### Behavioral checks

For a bug, demonstrate the failing scenario before changing it and exercise the
same scenario afterward. Build changed native modules before runtime checks.
Use deterministic regression tests where the real behavior has a suitable seam.
Throwaway probes are useful for boundaries and resource lifetimes; remove them
afterward. An isolated `FloatingWindow` proves its own path, not the actual drawer
host's sizing, input regions, clipping, shadows, or frame timing.

Choose the relevant rows; report which were actually exercised:

| Changed area | Required scenarios |
| --- | --- |
| Drawers / shared UI | Actual-host open/close, repeated and rapid tab switches, interrupted expand/collapse, all affected natural sizes, no orphaned overlays. |
| Media | Playing/paused/no player; known/unknown duration; seek where supported; title overflow; waveform fade-out/in and restart. |
| Calendar | Seven weekday/date columns aligned, six rows, month changes, repeated tab visits; use current font metrics rather than screenshot-specific dimensions. |
| Services / ownership | Activate/deactivate repeatedly; check freshness, cancellation latency, idle work, and stable descriptor/thread/connection counts. |
| Networking | Cached list and explicit rescan separately; concurrent readers; cached and newly discovered physical NICs mixed with virtual interfaces. Use fixtures instead of disconnecting the user's network. |
| Images / wallpaper | Large image and DPR/resize behavior; rapid interrupted wallpaper transitions; completed-capture release; retained rendering quality. |
| Hardware-specific behavior | Exercise available hardware and state what was unavailable, especially NVIDIA, external-display DDC, and multi-monitor layouts. |

For performance comparisons, keep player state, visible surfaces, display scale,
build type, and sampling interval comparable. Use interval CPU deltas rather
than lifetime `ps %CPU`; inspect PSS/RSS, per-thread activity, wakeups, and open
descriptors as appropriate. Report frame median, tail, and worst case. Repeated
hot reloads and a fresh restart are different memory baselines.

Inspect the real rendered surface and runtime logs. If the session locks or the
required hardware is absent, state the verification limit rather than counting
an unseen surface as a pass. Drain a probe's output continuously or redirect it to
a bounded-lifetime file: a full stdout pipe can block the process and mimic a
product hang. Keep temporary diagnostics opt-in and remove them before delivery.

## Delivery

- Preserve the commit convention: `module: change`. Put secondary changes,
  important causes, and side effects in the body; inspect recent history for
  module names.
- Describe the user-visible change, how to exercise it, and any breaking changes
  or tradeoffs in the PR. Update existing user documentation when behavior changes.
- Report only checks actually run, their results, and relevant coverage limits.
  Keep docs and comments concrete: paths, invariants, commands, and reasons;
  omit generated filler, stale benchmark promises, and unrelated rewrites.
- Leave no probe IPC handlers, test players, generated `__pycache__`, screenshots,
  fixture files, or accidental user-state changes from the task.
