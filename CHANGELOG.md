# Changelog

## 0.16.0

- **C14-snackBarPersist (default set).** Flutter defaults a `SnackBar`'s
  `persist` to `action != null`, so any snack bar with an action stays up
  until tapped and follows the person across screens. Lullaby's quick-log
  line sat there for minutes on the emulator; a fleet sweep found the
  same in Sundial (4), Peckish (1) and Trellis (3). Every `SnackBar(` with
  an `action:` must now say `persist:`. A check rather than an ohStyle
  helper: the next plain `SnackBar(` would bypass a helper silently, and
  a check fails loudly in every app. In the default set because every
  Flutter app was green on it when it landed; porch and Trellis, which
  list their checks explicitly, add it by name.

## 0.15.0

- **C7-assetText Latin fallback allowance
  (`FleetAppConfig.assetTextLatinFallback`).** A data file the app draws on
  purpose beyond its bundled faces, such as PunctumTemporis's list of
  place names (Vietnamese and other Latin Extended letters: Hà Nội, İzmir),
  relies on the engine's fallback fonts: the phone's system fonts natively,
  the shared Noto mirror on the web. Exempting the whole file would leave
  nothing checked (the check then fails, by design). The allowance passes
  only extended Latin (U+0100–U+02AF, U+0300–U+036F, U+1E00–U+1EFF) in the
  named file; every other character there is still checked (an arrow or a
  CJK name is still a finding), and the file counts as checked. A blank
  reason or a stale path is a finding.

## 0.14.0

- **C7-assetText (opt-in, `FleetCheck.c7AssetText`).** C7 swept the
  string literals in `lib/` and never saw the words that live in data
  files, so a deck title or a name list could print a box with every check
  green. The new check reads the app's `flutter: assets:` (directory
  entries ship only their direct files, as Flutter does) and checks what
  each text file draws: JSON string values (sniffed by content, so a
  `.ohcourse` counts; keys are identifiers and skipped), SVG `<text>` and
  `<tspan>` with character references decoded (comments and metadata are
  never drawn), and every character of any other UTF-8 file. Binary files
  are skipped; a text-named file that is not UTF-8 is a finding. The web
  emoji rule is C7's. `FleetAppConfig.assetTextExemptions` records a
  never-drawn asset with its reason; a blank reason or a stale path is a
  finding. It cannot pass by finding nothing: no readable bundled font, a
  declared asset missing on disk, and no text asset checked are all
  findings, and only a file that draws words counts as checked (an empty
  `.gitkeep` or an SVG with no `<text>` does not, which StillLife's
  `assets/icons/.gitkeep` showed). Outside every default set: enabling
  it in an app with no text assets would be a rule about nothing. Generalises Mantle's own
  `content_glyphs_test`. Proven red on Mantle with a `≤` seeded into
  `assets/data/spot.json`, green once reverted.

## 0.13.0

- **C13 pins the fallback-font path.** `fontFallbackBaseUrl` must be
  exactly `kFleetFontFallbackBaseUrl`, `/fonts/flutter-fallback/`. Every
  PWA is served from `levitatingflyfisher.github.io/<App>/`, and the user
  site at that origin's root (`OpenHearth/_ohsite_build`) now mirrors the
  engine's on-demand fallback fonts there once for the whole fleet, so a
  glyph the bundled fonts lack (ř, box drawing, CJK, emoji a user types)
  draws instead of showing a box while the engine retries a 404 every
  frame. An app-relative path (the old `fallback-fonts/`) resolves under
  `/<App>/`, where nothing is shipped, and is now a finding; so is a
  near miss such as a missing trailing slash. Absolute and
  protocol-relative URLs stay findings. Proven red on StillLife with its
  old bootstrap, green with the shared path.
- C7's doc comment no longer says the web serves no fallback fonts; the
  web emoji rule stands, for the offline and byte-cost reasons it gives.

## 0.12.0

- **C7 decodes escapes.** The sweep read each literal's raw runes, so
  `'Skip \u2192'` was plain ASCII to it and passed while the app drew a
  box. Non-raw literals now have `\uXXXX`, `\u{X…}` and `\xHH` resolved
  (escaped surrogate pairs become one code point) before coverage is
  checked; raw strings are left as written.
- **C7 drops the emoji exemption for apps that ship a web build.** Since
  C13 the web engine's fallback fonts come from the app's own origin,
  which serves none, so an emoji draws as a box there (and the engine
  re-requests the missing font every frame). An app with `web/index.html`
  now gets every emoji, zero-width joiner and variation selector its
  bundled fonts lack as a finding. Native-only apps keep the exemption.
  `undrawableIn` takes `web: true` for the same rule in an app's own
  tests. Caught, read-only across the fleet: StillLife (`→` in onboarding,
  the 👤 default avatar and the profile-avatar emoji set), PunctumTemporis
  (`→` in the date-range dialog), Lilt (`τ` in the solo results),
  Sundial (🌿 in profiles) and porch (activity emoji). Nine (Bulwark,
  Furrow, Glass, Hatch, Lullaby, Mantle, Peckish, Reckon, PrimingTrellis)
  stayed at zero findings.

## 0.11.0

- **C13 webSelfHosted (opt-in).** `FleetCheck.c13WebSelfHosted` fails an
  app whose web build would load from Google's CDNs: no
  `web/flutter_bootstrap.js` (Flutter's generated default fetches the
  Roboto fallback from `fonts.gstatic.com`, and CanvasKit from
  `www.gstatic.com` unless built with `--no-web-resources-cdn`), a loader
  config without relative `canvasKitBaseUrl` and `fontFallbackBaseUrl`, a
  Google CDN host in `web/`, a cross-origin `src`/`href` in `index.html`,
  or no bundled font for basic Latin (without the CDN Roboto, such an app
  draws no text on the web). An absent `web/`, `index.html`, bootstrap or
  loader call is a finding. Caught WeatherGlass, whose PWA fetched
  CanvasKit and Roboto from gstatic on every load.

## 0.10.0

- **Strict C11 exemptions.** `FleetAppConfig.barLabelExemptions` records
  keyed bar controls whose visible word the static scan cannot see (a face
  built by a widget defined elsewhere), as `'lib/path.dart#<Key string>'`
  with a reason. An empty reason, and an exemption matching no finding, are
  findings. Written for Trellis's reader mode picker, whose `_BarMenuFace`
  shows the current mode as a word.

## 0.9.0

- **C11 strict mode (opt-in).** `FleetCheck.c11StrictBarLabels` runs C11
  with `strict: true`: a tooltip no longer satisfies it. An icon-only bar
  button, or a `PopupMenuButton` whose face shows no `Text`, is a finding
  naming `OhBarAction` / `OhBarOverflow` (openhearth_design 0.8.0). Use it
  instead of `c11IconLabels`; it is outside every default set. Seeded red
  on a tooltip-only `IconButton` and an icon-only `PopupMenuButton`; a
  read-only run across the fleet found 16 real offenders in Reckon,
  Trellis, StillLife and Furrow (see README) and none in nine apps.

## 0.8.1

- **C7 fonts reads package fonts.** ohStyle 0.7.1 ships Lora and Nunito as
  `openhearth_design` package fonts, so an app can drop its own copies —
  but C7 parsed only the app's pubspec and called such an app "no bundled
  font families declared". C7 (and `bundledFontCoverage`) now also resolves
  `openhearth_design` through the app's `.dart_tool/package_config.json`
  (falling back to its pubspec `path:` dependency when `.dart_tool` is
  absent) and includes that package's families as
  `packages/openhearth_design/<Family>`. Every family, app or package, is
  intersected: text in an `OhTypography` style lands in the package face.
  Still fails closed: no app fonts and no package fonts is a finding, and a
  package font file missing from disk is a finding naming the package.
  Checked read-only on Sundial, Furrow, PunctumTemporis, Reckon, Hatch and
  Peckish (zero findings, unchanged), and on a scratch app with no local
  fonts against the real ohStyle faces (a seeded `≤` is flagged).

## 0.8.0

Every check below ships OUTSIDE `FleetAppConfig.defaultChecks`: an app
opts in by adding it to `checks:` once the rollout has made that app green.
Each was proven on a real tree without editing any app (scratch copies and
historical `git archive` snapshots only).

- **C9 routes (new)**: every screen has a way in. A `GoRoute` with a
  builder must be reached by a matching path literal in authored `lib/`
  code, a `goNamed`/`pushNamed` of its name, `goBranch` (stateful-shell
  branch roots) or go_router's default `/`. Caught Lilt's `/name/:nameId`
  at the audit-time snapshot (fixed since in 17ecef5), and on today's trees
  finds StillLife's `/photo/view` (declared, named `photoViewer`, never
  navigated to — the viewer is pushed with `MaterialPageRoute` instead).
  Lullaby agrees with its own `router_doors_test` (zero orphans); deleting
  one door in a scratch copy of Lullaby turns it red. Deliberate door-less
  routes are recorded in `FleetAppConfig.routeExemptions` with a reason.
- **C10 rawErrors (new)**: no raw exception as user-visible text. Reads the
  first positional argument of `Text`/`SelectableText`, `TextSpan(text:)`
  and `errorText:`; flags `$e`, `${error}`, `e.toString()`,
  `${snapshot.error}` and friends, with `e`/`ex` only where the file binds
  them as an error. Findings point to `OhErrorState` /
  `ohFriendlyErrorMessage`. Today's trees: Lilt 7 (exactly the audit's six
  screens plus `app.dart`), Lullaby 22, Peckish 1, StillLife 38, Reckon 31,
  Furrow 8, Bulwark 6, Sundial 6, Glass 2; Mantle, Hatch,
  PunctumTemporis, PrimingTrellis and porch 0.
- **C11 iconLabels (new)**: an icon-only button in `AppBar`/`SliverAppBar`
  `actions:` needs a tooltip or a visible `Text` in its icon; the finding
  recommends icon plus short label (`TextButton.icon`) or a worded
  `PopupMenuButton`, per the operator's item-45 ruling. `PopupMenuButton`
  and labelled buttons are compliant. Today's trees: StillLife 10,
  Lullaby 8, Lilt 1, Furrow 1; every other app 0.
- **C12 accentVsError (new)**: the accent must not BE the error colour.
  Each accent vs ohStyle's urgency role of the same brightness must stay
  CIEDE2000 ≥ 12. Per the operator's colour ruling, red may be both warmth
  and error, separated by "error = colour + icon + word" rather than hue,
  so the floor only catches an accent that is effectively the error red;
  colour-blind simulation is an informational note on a failing finding,
  not a failure. `fromSeed` themes are judged by the primary Flutter
  actually renders, not the seed. `FleetAppConfig.accentColors`
  (`FleetAccent.light/dark`) records accents detection cannot resolve,
  user presets included. Today's trees: every app passes (ohStyle 0.7.0
  warmth 14.1 light / 16.6 dark) except Reckon and PunctumTemporis, which
  must record `accentColors`; a scratch copy of Glass seeded with red500
  renders a primary 9.7 from it and goes red.
- **C5 primary-action profile (item 24)**: `A11ySweepProfile`
  (`narrowLargeText` 320×640 at 1.0/3.0; `primaryAction` 360×640 at 1.3)
  and `runPrimaryActionSweep`, which asserts the primary action is in the
  tree and reachable (tappable, or scrolled into view) at 360dp × 1.3 and
  then runs the 320dp × 3.0 overflow sweep. Reckon's onboarding could not
  be finished at 1.3×: a `Column` with a `Spacer` and no scroll view
  clipped its only working control off the bottom, and no sweep covered
  it.
  The opt-in `FleetCheck.c5PrimaryScreens` requires every class listed in
  `FleetAppConfig.primaryActionScreens` to be named inside such a call in
  `test/`: listing Reckon's `ModelOnboardingScreen` or Lullaby's
  `FeedingLogScreen` today is a finding; a scratch copy with the sweep
  written is clean. `runA11ySweep` is unchanged.
- **`canonicalTokensByNameFrom`** (style.dart): the canonical tokens by
  name, from the same colors.dart as `canonicalTokenValuesFrom` — one
  parser, not a second.

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
