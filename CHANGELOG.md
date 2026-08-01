# Changelog

## 0.7.0

- **C8 (new)**: no bare `IconButton.filled(`/`IconButton.filledTonal(` in an
  app that depends on `openhearth_design`. ohStyle's `OhTheme` sets an
  app-wide `iconTheme` color of `primary`; in Flutter 3.38.7 that ambient
  color is injected above `IconButton`'s own variant defaults, so a bare
  `IconButton.filled` paints its glyph the same color as its own fill —
  invisible, tappable, and reported by a device tester as "blank circles".
  `IconButton.filledTonal` collides the same way with poor contrast instead
  of invisibility. `OhIconButton.filled`/`OhIconButton.filledTonal` pin the
  correct foreground; C8 is the guard that stops the next
  `IconButton.filled(` from reopening the collision under a green suite.
  Confirmed against the fleet's own trees: Furrow (1 site), Peckish (1),
  StillLife (4), PrimingTrellis (2) — all real, none fixed by this check
  itself.

  Scans `lib/` only — a regression test proving the collision exists must
  be free to construct a bare `IconButton.filled` — and is gated on the
  app's pubspec actually depending on `openhearth_design`; an app with a
  different theme has no collision to flag.

  C8 ships OUTSIDE the default check set, exactly like C7: it only bites
  once an app has adopted `OhIconButton`, so defaulting it on would flag
  every app still on the bare constructor. There is no dedicated combined
  set — every app that currently has the bug already carries C7 (via
  `withBundledFonts` or its own `checks:` literal), so an app opts in by
  adding `FleetCheck.c8IconButtons` to whatever set it already runs.

## 0.6.2

- **C4 v2**: merged-manifest discovery now reads both AGP layouts —
  `merged_manifests/release` (plural, older AGP) and
  `merged_manifest/release` (singular, AGP 8) — instead of silently
  skipping the whole release-surface comparison on modern toolchains.
  Found when Trellis's first release build produced the singular layout
  and the recorded merged allowlist compared against nothing.

## 0.6.1

- **C6**: the CI sub-check now reads workflows from the directory GitHub
  reads them from — the nearest ancestor carrying `.git` — instead of
  insisting on `.github/workflows` under the app root. Every flat-layout
  app (app root = repo root) is judged exactly as before; a nested app
  root (the PrimingTrellis `app/` layout) is judged by the CI that
  actually runs rather than asked to keep a decorative copy the runner
  never reads.

## 0.6.0

- **C4**: a store listing may not claim more privacy than the manifest
  delivers. If `fastlane/.../full_description.txt` says the app "asks for no
  network permission" while the source manifest declares
  `android.permission.INTERNET`, that is a finding. Eight apps make this
  claim to F-Droid; a stranger reading the listing cannot check it, so the
  suite checks it for them. Apps with no listing are unaffected.

## 0.5.1

- **C6**: also fail when generated files are still TRACKED by git, not just
  when the `.gitignore` rule is missing. `.gitignore` governs untracked
  paths only, so adding the rule leaves every already-committed file exactly
  where it was — Lilt and Mantle sat in precisely that state, rule present,
  check green, 14 generated files still committed between them. A rule about
  a rule is not a guard.

  Shells out to `git ls-files`; reports nothing when git is absent or the
  directory is not a repo, since that is genuinely unknowable there.

## 0.5.0

- **C6**: an app that runs `build_runner` must ignore `*.g.dart`. CI and
  every local build regenerate, so a committed generated file is a second
  source of truth that nothing keeps honest — StillLife had 14 tracked,
  Lullaby 8, Reckon 1, and four more apps had no rule stopping the same
  drift. Apps with no `build_runner` are exempt: a rule about output that
  is never produced is a rule about nothing.

## 0.4.0

- **C7 (new)**: the bundled-font glyph guard. An app that bundles its type
  does not fall back to a web font, so a character outside the bundled
  cmaps is a tofu box on someone's phone. C7 parses each declared family's
  regular weight (format-4 cmap), intersects them, and sweeps every string
  literal under `lib/`. Emoji are exempt (the platform's colour font draws
  them) and so are `RegExp(` lines and anything marked `// not-rendered`
  (a character class is parsed, never painted).

  Written so it cannot pass by finding nothing: no declared fonts, a
  missing font file, an implausibly small cmap, and an empty `lib/` are
  all findings rather than silent empties.

  `FleetAppConfig.defaultChecks` and `FleetAppConfig.withBundledFonts` name
  the two sets, so opting in is one line per app rather than eleven copies
  of a six-element literal.

  C7 ships OUTSIDE the default check set — it only applies to apps that
  bundle type, and defaulting it on would enable it for every consumer
  the moment this package changed. Apps opt in via `checks:`.

  `bundledFontCoverage` and `undrawableIn` are exported so an app can
  assert the same way about strings the sweep cannot see (an enum's
  label, a generated month table).

## 0.3.1

- **C4**: a `<uses-permission … tools:node="remove"/>` element is a
  merge-time STRIP of a plugin-injected permission, not a declaration —
  the source-manifest check no longer counts it (the Peckish scenario:
  the camera plugin injects RECORD_AUDIO, the app strips it; C4 was
  flagging the strip itself). The strip's real effect stays verified by
  the merged-manifest comparison.

## 0.3.0

(Section written retroactively in 0.3.1.)

- **C4 v2 — the merged-manifest surface**: apps can record
  `mergedAndroidPermissions` (source permissions plus what plugins and
  the manifest merge inject); when a release merged manifest exists
  under build/, every ABI variant is compared both directions.
- **C3 in CI** fleet-wide support.

## 0.2.1

- **C2 backup**: the serializer-declaration anchor is logical-line, not
  physical-line. 0.2.0's `[^{;\n]*` clause anchor could not cross the
  newline `dart format` inserts when it wraps the fleet's >80-col
  declarations (`class FooBackupSerializer\n    implements ...`), so
  every adopted app failed C2 for conforming code. The anchor now stops
  at the header's `{`/`;` instead of at newlines — still rejecting the
  newline-spanning non-declaration matches 0.2.0 shut out.

## 0.2.0

The checks now scan code, not comments — a review pass found that most
source scans could be satisfied (or false-alarmed) by comments, strings,
or superstring names, including by this package's own conformant fixture.

- **C2 backup**: all sub-checks run on comment-stripped, string-blanked
  Dart source (new newline-preserving `strippedDartSource`); the
  serializer must be a real one-line class declaration
  (`BackupSerializerRegistry` and newline-spanning matches no longer
  count); `runStartupMaintenance` must be a call site.
- **C1 style**: pubspec dependency walk skips `#` comment lines and
  examines every occurrence of the key (`dependency_overrides` included);
  the canonical path must *end* at `ohStyle/openhearth_design` on a
  segment boundary (`evil/ohStyle/openhearth_design-fork` shapes fail);
  the retyped-token scan ignores comments/strings, and the hex pattern
  gained a right boundary so 16-digit masks no longer half-match.
- **C4 permissions**: `<!-- -->` comments are stripped before the
  uses-permission scan; single-quoted `android:name` is recognized.
- **C6 harness**: the flutter-version scan is comment-aware; a
  `${{ ... }}` value is reported as its own expression-pin finding; a
  workflow using subosito/flutter-action with no `flutter-version` at all
  is now a finding.
- **Runner**: `runFleetConformance` evaluates all checks once per suite
  (lazy shared memo) instead of once per test, and a check that throws
  becomes a finding on that check alone instead of failing all five tests.
- **Canonical flutter_test_config template**: the FontManifest family loop
  guards each family individually — one family's failure logs and
  continues instead of aborting the families after it (MaterialIcons loads
  first, so its failure used to silently kill Lora/Nunito). Apps re-sync
  their copies from this constant.

## 0.1.0

Initial release: the fleet-standardization campaign's enforcement layer.
C1 style (canonical design package, no vendored forks, no retyped token
literals), C2 backup (retention-spec conformance incl. honest merge-restore
copy), C3 size budgets (gzip JS + arm64 APK ratchet), C4 Android permission
allowlists, C5 320dp×3.0 accessibility sweep helper, C6 harness canon
(flutter_test_config / analysis_options / CI pin), all behind one
`runFleetConformance(FleetAppConfig)` call per app.
