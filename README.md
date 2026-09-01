# oh_fleet_conformance

The OpenHearth fleet's standards, as tests that can fail — never as
documents that drift.

An app adopts the whole suite with one file:

```dart
// test/fleet_conformance_test.dart
import 'package:oh_fleet_conformance/oh_fleet_conformance.dart';

void main() => runFleetConformance(const FleetAppConfig(
      appId: 'sundial',
      styleTier: StyleTier.tokens,
      androidPermissions: {
        'android.permission.POST_NOTIFICATIONS',
        'android.permission.VIBRATE',
      },
    ));
```

## The checks

| Check | Enforces |
|---|---|
| C1 style | The design grammar has ONE source of truth: canonical `openhearth_design` consumed by sibling path (no vendored forks — a fork's hues silently diverged once already), and no retyped token hex literals in `lib/`. |
| C2 backup | `BACKUP_RETENTION_SPEC.md`'s enforcement layer: sanctuary_backup_ui ≥ 0.2.0 actually relocked, serializer on the shared `BackupEnvelope` + `PreviewableBackupSerializer`, merge-restore apps override the destructive confirm copy, the startup maintenance hook exists. |
| C3 budgets | Measure–budget–ratchet: `budgets.json` baselines vs on-disk artifacts (gzipped `main.dart.js`, arm64 APK). Artifacts absent → skip; budgets absent or zeroed → fail. |
| C4 permissions | The app's exact `<uses-permission>` surface, both directions — the no-INTERNET and zero-permission claims are tests, not promises. Since 0.3.0 the check also covers the **release merged manifest** (what plugins inject) when the app records `mergedAndroidPermissions` and an APK build has left `build/app/intermediates/merged_manifests/release/**` on disk; release variants only — debug merged manifests are dev scaffolding and often stale. To record a surface: build the APK, run the conformance test, and record exactly the permissions the findings name. |
| C5 a11y | `runA11ySweep` — the 320dp × 3.0 text-scale sweep template, including opened dialogs (where the fleet's overflow bugs actually live). |
| C5 primaryScreens | *(opt-in — add `FleetCheck.c5PrimaryScreens` and list `FleetAppConfig.primaryActionScreens`)* The release gate for primary-action screens: `runPrimaryActionSweep` sweeps at 360dp × 1.3 (`A11ySweepProfile.primaryAction`) requiring the primary action to be present and tappable — scrolled into view if a scrollable can — and then runs the 320dp × 3.0 overflow sweep as well. The check requires each listed screen class to exist in `lib/` and to be named inside a `runPrimaryActionSweep(` call under `test/`. It proves the sweep is written; running it proves it passes. An empty list is a finding. |
| C6 harness | Canonical `flutter_test_config.dart` (the FontManifest-aware variant — divergence means goldens render different fonts per app), canonical `analysis_options.yaml` (recorded tighter overrides allowed), CI exists and pins the real fleet Flutter version. |
| C7 fonts | *(opt-in — `FleetAppConfig.withBundledFonts`)* Every character printed under `lib/` is drawable by the app's bundled fonts — its own `fonts:` block plus `openhearth_design`'s package fonts, resolved via `.dart_tool/package_config.json` (format-4 cmap intersection); emoji and `RegExp(`/`// not-rendered` lines are exempt. Written so it cannot pass by finding nothing. |
| C8 iconButtons | *(opt-in — add `FleetCheck.c8IconButtons` to `checks:`)* No bare `IconButton.filled(`/`IconButton.filledTonal(` under `lib/` in an app that depends on `openhearth_design` — ohStyle's ambient `iconTheme` paints the glyph the same color as the button's own fill. Use `OhIconButton.filled`/`OhIconButton.filledTonal`, which pin the correct foreground. Scoped to `lib/` (a collision regression test in `test/` must be free to construct the bare form) and gated on the `openhearth_design` dependency actually being present. |
| C9 routes | *(opt-in — add `FleetCheck.c9Routes`)* Every `GoRoute` screen under `lib/` has a way in: a path literal in authored code that matches it (`:param` matches any segment; comments never count), a `goNamed`/`pushNamed` of its name, `goBranch` for stateful-shell branch roots, or go_router's default `/`. Redirect-only routes are not screens. Deliberate door-less routes (deep-link only) go in `FleetAppConfig.routeExemptions` with a reason; an empty reason, a stale key and an exemption whose route has since gained a door are findings. Cannot pass with no `GoRoute` found. |
| C10 rawErrors | *(opt-in — add `FleetCheck.c10RawErrors`)* No raw exception as user-visible text: `Text('Error: $e')`, `Text(e.toString())`, `'${snapshot.error}'` in a `Text`/`SelectableText` (so every `SnackBar(content: Text(...))`), `TextSpan(text:)` or `errorText:`. `e`/`ex` count only where the file binds them as an error (`catch (e`, `error: (e, st)`), so `list.map((e) => Text('$e'))` stays quiet. Findings point to `OhErrorState` / `ohFriendlyErrorMessage` (openhearth_design 0.7.0). Stored-then-shown errors are a recorded false negative. |
| C11 iconLabels | *(opt-in — add `FleetCheck.c11IconLabels`)* Every icon-only button (`IconButton` and variants, `OhIconButton.filled`/`.filledTonal`) inside an `AppBar`/`SliverAppBar` `actions:` list carries a `tooltip:` or a visible `Text` in its `icon:`. The tooltip is the floor, not the target: findings recommend icon plus short label (`TextButton.icon`) and a worded `PopupMenuButton` for rare actions (operator ruling, item 45). Static and conservative: actions built in a helper or variable are not seen. Cannot pass with no app bar found. |
| C11 strictBarLabels | *(opt-in — add `FleetCheck.c11StrictBarLabels` **instead of** `c11IconLabels`; its findings are a superset)* Holds the ruling, not the floor: a tooltip no longer passes. Every icon-only button in `actions:` is a finding unless its `icon:` shows a `Text`, and so is a `PopupMenuButton` with no `child:` that shows a `Text`. The fix it names is openhearth_design's `OhBarAction` (icon plus a short label; the word folds into the tooltip only above 1.5x text) and `OhBarOverflow` (the worded More menu). Same static reach as C11. A keyed control whose word the scan cannot see (a face built by a widget defined elsewhere, like Trellis's reader mode picker) is exempted in `FleetAppConfig.barLabelExemptions` as `'lib/path.dart#<Key string>'` with its reason; an empty reason or an exemption that matches nothing is a finding. On and green in Reckon, Trellis (one recorded exemption: the reader's mode picker), StillLife and Furrow, whose 16 tooltip-only commands were migrated to `OhBarAction` / `OhBarOverflow`. Lilt, porch, Bulwark, Lullaby, Sundial, Peckish, Glass, Mantle and PunctumTemporis were green in a read-only run. |
| C12 accentVsError | *(opt-in — add `FleetCheck.c12AccentVsError`)* Each accent the app paints as primary must stay CIEDE2000 ≥ 12 from ohStyle's urgency role of the same theme brightness (`OhColorRoles.light.urgency` for light accents, `hearthDark`/`night` for dark). **Why only 12:** the operator ruled that red may be both warmth and error; they are told apart by the style guide's pairing rule — an error is colour **plus icon plus word** — not by hue alone. So C12 fails only when the accent is effectively the error colour itself (12 is just past the ~10 "different at a glance" level; ohStyle 0.7.0's warmth clears it at 14.1 light, 16.6 dark). For the same reason colour-blind simulation (protan/deutan/tritan, Machado 2009) is an informational note on a failing finding, never a failure: a colour-blind viewer relies on the icon and the word, which is why they are mandatory. Accents come from `FleetAppConfig.accentColors` (`FleetAccent.light/dark`, as rendered, presets included) or are detected: `ColorScheme.fromSeed` judged by its rendered primary, `ColorScheme(primary:)`, `OhTheme.*(appAccent:)` or the role's warmth. An accent it cannot resolve is a finding. |

Every deliberate divergence is a recorded field on `FleetAppConfig` — one
place to read an app's posture, nothing scattered.

Findings are returned, not thrown: one failing check reports *every*
violation in its area with file/line specifics.
