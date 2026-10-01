import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'checks/accent_vs_error.dart';
import 'checks/asset_text.dart';
import 'checks/android_permissions.dart';
import 'checks/backup.dart';
import 'checks/budgets.dart';
import 'checks/fonts.dart';
import 'checks/harness.dart';
import 'checks/icon_buttons.dart';
import 'checks/icon_labels.dart';
import 'checks/primary_screens.dart';
import 'checks/raw_errors.dart';
import 'checks/routes.dart';
import 'checks/snack_bars.dart';
import 'checks/style.dart';
import 'checks/web_self_hosted.dart';
import 'findings.dart';

/// How an app consumes the design grammar (spec §8, P1 two-tier standard).
///
/// The tiers change WHICH waves migrate an app, not which checks run —
/// both tiers require the canonical package and forbid retyped token
/// literals; construction style (OhTheme vs local ThemeData over package
/// tokens) stays an app decision recorded here.
enum StyleTier { full, tokens }

/// The individually enableable checks.
///
/// Waves earn checks progressively (an app that adopted backup v0.2.0 but
/// not yet the style grammar enables c2 without c1); the campaign's ship
/// gate is every app on the full set. C5 (the 320dp sweep) is a helper
/// template, not a config-driven check — see `runA11ySweep` — except its
/// item-24 half, [c5PrimaryScreens], which checks that the screens an app
/// lists are actually swept by `runPrimaryActionSweep`.
///
/// C7 is deliberately OUTSIDE the default set: it only makes sense for an
/// app that bundles its own type, and switching it on by default would
/// turn it on for every consumer the moment this package changes. Apps opt
/// in; the default flips once they all have.
///
/// C8 is deliberately OUTSIDE the default set too, for the same reason: it
/// only bites once an app has adopted `OhIconButton` as the fix, and
/// enabling it fleet-wide the moment this package changed would flag every
/// app still on the bare constructor rather than the ones that have moved.
/// It has no dedicated combined set (contrast [FleetAppConfig.withBundledFonts]):
/// every app that currently has the bug already carries C7, so an app
/// opting in adds `FleetCheck.c8IconButtons` straight to its own `checks:`
/// set alongside whatever else it already runs.
///
/// C9 onward (0.8.0) are opt-in on the same terms: each is added to an
/// app's `checks:` set by the rollout that makes that app green, and the
/// default flips only when every app is.
enum FleetCheck {
  c1Style,
  c2Backup,
  c3Budgets,
  c4Permissions,
  c6Harness,
  c7Fonts,
  c8IconButtons,
  c9Routes,
  c10RawErrors,
  c11IconLabels,

  /// C11's strict mode (opt-in, never in a default set): a tooltip no
  /// longer passes; every bar command shows its word (`OhBarAction`, or
  /// `OhBarOverflow` for a menu). Use it INSTEAD of [c11IconLabels] — its
  /// findings are a superset.
  c11StrictBarLabels,
  c12AccentVsError,

  /// Item 24's release-gate half of C5: the listed primary-action screens
  /// are swept at 360dp × 1.3 by `runPrimaryActionSweep`.
  c5PrimaryScreens,

  /// C13 (opt-in): the web build loads nothing from Google's CDNs —
  /// `web/flutter_bootstrap.js` points CanvasKit and fallback fonts at the
  /// app's own origin, and the app bundles a text font.
  c13WebSelfHosted,

  /// C7-assetText (opt-in): C7's glyph guard over the app's bundled text
  /// assets (JSON string values, SVG `<text>`, plain text files), not only
  /// the literals in `lib/`. Only for an app that ships text assets: with
  /// none, it is a finding, never a free pass.
  c7AssetText,

  /// C14: every `SnackBar` with an `action:` states `persist:` (Flutter
  /// otherwise keeps it up until tapped, across screens). In the default
  /// set: every Flutter app in the fleet was green when it landed.
  c14SnackBarPersist,
}

/// One app's recorded standardization posture.
///
/// Every deliberate divergence from fleet canon lives HERE, in one place
/// reviewers can read — not scattered through the app as unexplained
/// deltas.
class FleetAppConfig {
  final String appId;

  final StyleTier styleTier;

  /// C4 — the app's exact `<uses-permission>` surface. Empty set = the
  /// zero-permission claim, enforced.
  final Set<String> androidPermissions;

  /// C4 v2 — the MERGED-manifest surface (source permissions PLUS what
  /// plugins and the manifest merge inject, e.g. WAKE_LOCK from
  /// notifications or the per-app DYNAMIC_RECEIVER_NOT_EXPORTED synthetic).
  /// Null = not yet recorded, merged check off; the comparison only bites
  /// when an APK build has left a merged manifest under build/.
  final Set<String>? mergedAndroidPermissions;

  /// C2 — true only for apps whose restore is upsert-merge (StillLife):
  /// they must override the package's destructive confirm copy.
  final bool mergeSemanticsRestore;

  /// C2 — false only for apps driving the vault from their own service
  /// in their own idiom (PunctumTemporis).
  final bool expectStartupMaintenance;

  /// C6 — true for the recorded allowed-tighter analysis configs
  /// (Reckon/PunctumTemporis/StillLife).
  final bool analysisOptionsOverrideRecorded;

  /// C1 — token values the app may retype because its signature accent
  /// coincides with a canonical token (Sundial's sage IS sage500).
  final Set<int> allowedTokenLiterals;

  /// C1 — path to the canonical design package, relative to the app root.
  ///
  /// Every app in the fleet now sits directly under `OpenHearth/`, so the
  /// default holds and nothing overrides this. It stays configurable for the
  /// next app that lands somewhere unusual — but an app that needs it is an
  /// app that will quietly miss fleet-wide sweeps, so prefer moving the app.
  final String designPackagePath;

  final String requiredCiFlutterVersion;

  final Set<FleetCheck> checks;

  /// C9 — routes that deliberately have no in-app door, keyed by full path
  /// (or route name) with the reason: `{'/share/:id': 'deep link from the
  /// share sheet only'}`. An empty reason, a key no route declares, and a
  /// key whose route has since gained a door are all findings.
  final Map<String, String> routeExemptions;

  /// C12 — every accent the app paints as its primary, per theme
  /// brightness, as RENDERED (after any `fromSeed` tone mapping), including
  /// user-selectable presets. Empty = detect from `lib/`; recording this
  /// replaces detection entirely.
  final List<FleetAccent> accentColors;

  /// C5-primaryScreens — widget class names of the screens whose primary
  /// action must survive 360dp × 1.3 (onboarding, the main add/log
  /// screen). Each must be pumped inside a `runPrimaryActionSweep(` call
  /// under `test/`.
  final Set<String> primaryActionScreens;

  /// C11 strict — bar controls whose word the static scan cannot see (a
  /// face built by a widget defined elsewhere), keyed
  /// `'lib/path.dart#<Key string>'`, with the reason. An empty reason and a
  /// key that matches no finding are findings.
  final Map<String, String> barLabelExemptions;

  /// C7-assetText — asset paths (as shipped, `assets/x.json`) whose text is
  /// never drawn, with the reason. A blank reason and a path that is not a
  /// shipped text asset are findings.
  final Map<String, String> assetTextExemptions;

  /// C7-assetText — asset paths whose extended Latin letters are drawn on
  /// purpose through the engine's fallback fonts (place names), with the
  /// reason. Everything else in the file is still checked.
  final Map<String, String> assetTextLatinFallback;

  /// What every app runs. C7 is absent on purpose — see [FleetCheck].
  static const defaultChecks = {
    FleetCheck.c14SnackBarPersist,
    FleetCheck.c1Style,
    FleetCheck.c2Backup,
    FleetCheck.c3Budgets,
    FleetCheck.c4Permissions,
    FleetCheck.c6Harness,
  };

  /// [defaultChecks] plus the bundled-font guard — the set for any app that
  /// ships its own type and therefore has no web-font fallback to save it.
  static const withBundledFonts = {...defaultChecks, FleetCheck.c7Fonts};

  const FleetAppConfig({
    required this.appId,
    required this.styleTier,
    required this.androidPermissions,
    this.mergedAndroidPermissions,
    this.mergeSemanticsRestore = false,
    this.expectStartupMaintenance = true,
    this.analysisOptionsOverrideRecorded = false,
    this.allowedTokenLiterals = const {},
    this.designPackagePath = '../ohStyle/openhearth_design',
    this.requiredCiFlutterVersion = '3.38.7',
    this.checks = defaultChecks,
    this.routeExemptions = const {},
    this.accentColors = const [],
    this.primaryActionScreens = const {},
    this.barLabelExemptions = const {},
    this.assetTextExemptions = const {},
    this.assetTextLatinFallback = const {},
  });
}

/// Pure evaluation of every enabled check — the testable core behind
/// [runFleetConformance].
Map<FleetCheck, List<ConformanceFinding>> collectFleetFindings(
  FleetAppConfig config, {
  required Directory root,
}) {
  final results = <FleetCheck, List<ConformanceFinding>>{};
  for (final check in config.checks) {
    results[check] = _guarded(
      check,
      () => switch (check) {
        FleetCheck.c1Style => _styleFindings(config, root),
        FleetCheck.c2Backup => checkBackupConformance(
            root: root,
            mergeSemanticsRestore: config.mergeSemanticsRestore,
            expectStartupMaintenance: config.expectStartupMaintenance,
          ),
        FleetCheck.c3Budgets => checkSizeBudgets(root: root),
        FleetCheck.c4Permissions => checkAndroidPermissions(
            root: root,
            allowlist: config.androidPermissions,
            mergedAllowlist: config.mergedAndroidPermissions,
          ),
        FleetCheck.c6Harness => checkHarnessCanon(
            root: root,
            analysisOptionsOverrideRecorded:
                config.analysisOptionsOverrideRecorded,
            requiredCiFlutterVersion: config.requiredCiFlutterVersion,
          ),
        FleetCheck.c7Fonts => checkFontCoverage(root: root),
        FleetCheck.c8IconButtons => checkNoBareIconButtonVariants(root: root),
        FleetCheck.c14SnackBarPersist => checkSnackBarPersist(root: root),
        FleetCheck.c9Routes => checkRouteReachability(
            root: root,
            exemptions: config.routeExemptions,
          ),
        FleetCheck.c10RawErrors => checkNoRawErrorText(root: root),
        FleetCheck.c11IconLabels => checkAppBarIconLabels(root: root),
        FleetCheck.c11StrictBarLabels => checkAppBarIconLabels(
            root: root,
            strict: true,
            exemptions: config.barLabelExemptions,
          ),
        FleetCheck.c12AccentVsError => checkAccentVsError(
            root: root,
            designPackage: Directory('${root.path}/${config.designPackagePath}'),
            declared: config.accentColors,
          ),
        FleetCheck.c5PrimaryScreens => checkPrimaryScreenSweeps(
            root: root,
            screens: config.primaryActionScreens,
          ),
        FleetCheck.c13WebSelfHosted => checkWebSelfHosted(root: root),
        FleetCheck.c7AssetText => checkAssetTextCoverage(
            root: root,
            exemptions: config.assetTextExemptions,
            latinFallback: config.assetTextLatinFallback,
          ),
      },
    );
  }
  return results;
}

/// A check that throws must fail as a finding on THAT check — never
/// propagate and take the four unrelated checks (and their tests) down
/// with it.
List<ConformanceFinding> _guarded(
  FleetCheck check,
  List<ConformanceFinding> Function() evaluate,
) {
  try {
    return evaluate();
  } catch (e) {
    return [
      ConformanceFinding(
        _checkLabel(check),
        'check threw instead of reporting findings: $e — fix the check or '
        'the input it was reading',
      ),
    ];
  }
}

String _checkLabel(FleetCheck check) => switch (check) {
      FleetCheck.c1Style => 'C1-style',
      FleetCheck.c2Backup => 'C2-backup',
      FleetCheck.c3Budgets => 'C3-budgets',
      FleetCheck.c4Permissions => 'C4-permissions',
      FleetCheck.c6Harness => 'C6-harness',
      FleetCheck.c7Fonts => 'C7-fonts',
      FleetCheck.c8IconButtons => 'C8-iconButtons',
      FleetCheck.c14SnackBarPersist => 'C14-snackBarPersist',
      FleetCheck.c9Routes => 'C9-routes',
      FleetCheck.c10RawErrors => 'C10-rawErrors',
      FleetCheck.c11IconLabels => 'C11-iconLabels',
      FleetCheck.c11StrictBarLabels => 'C11-strictBarLabels',
      FleetCheck.c12AccentVsError => 'C12-accentVsError',
      FleetCheck.c5PrimaryScreens => 'C5-primaryScreens',
      FleetCheck.c13WebSelfHosted => 'C13-webSelfHosted',
      FleetCheck.c7AssetText => 'C7-assetText',
    };

List<ConformanceFinding> _styleFindings(FleetAppConfig config, Directory root) {
  final findings = checkCanonicalDesignPackage(root: root).toList();
  // A missing canonical package must fail the check loudly, never crash
  // the suite or pass vacuously.
  try {
    final canonical = canonicalTokenValuesFrom(
      Directory('${root.path}/${config.designPackagePath}'),
    );
    findings.addAll(checkNoRetypedTokenLiterals(
      root: root,
      canonicalTokenValues: canonical,
      allowed: config.allowedTokenLiterals,
    ));
  } on StateError catch (e) {
    findings.add(ConformanceFinding('C1-style', e.message));
  }
  return findings;
}

/// Registers one test per enabled check. An app's entire conformance
/// surface is this one call in `test/fleet_conformance_test.dart`:
///
/// ```dart
/// void main() => runFleetConformance(const FleetAppConfig(...));
/// ```
void runFleetConformance(FleetAppConfig config, {Directory? root}) {
  final appRoot = root ?? Directory.current;
  // One shared evaluation per suite, computed lazily inside the first test
  // that needs it: five tests re-running collectFleetFindings meant five
  // rounds of identical filesystem work for no extra signal.
  Map<FleetCheck, List<ConformanceFinding>>? memo;
  group('fleet conformance (${config.appId})', () {
    for (final check in config.checks) {
      test(check.name, () {
        final findings =
            (memo ??= collectFleetFindings(config, root: appRoot))[check]!;
        expect(
          findings,
          isEmpty,
          reason: findings.map((f) => '\n  $f').join(),
        );
      });
    }
  });
}
