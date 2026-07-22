import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'checks/android_permissions.dart';
import 'checks/backup.dart';
import 'checks/budgets.dart';
import 'checks/harness.dart';
import 'checks/style.dart';
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
/// template, not a config-driven check — see `runA11ySweep`.
enum FleetCheck { c1Style, c2Backup, c3Budgets, c4Permissions, c6Harness }

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

  /// C1 — path to the canonical design package, relative to the app root
  /// (StillLife sits outside OpenHearth/ and needs the longer hop).
  final String designPackagePath;

  final String requiredCiFlutterVersion;

  final Set<FleetCheck> checks;

  const FleetAppConfig({
    required this.appId,
    required this.styleTier,
    required this.androidPermissions,
    this.mergeSemanticsRestore = false,
    this.expectStartupMaintenance = true,
    this.analysisOptionsOverrideRecorded = false,
    this.allowedTokenLiterals = const {},
    this.designPackagePath = '../ohStyle/openhearth_design',
    this.requiredCiFlutterVersion = '3.38.7',
    this.checks = const {
      FleetCheck.c1Style,
      FleetCheck.c2Backup,
      FleetCheck.c3Budgets,
      FleetCheck.c4Permissions,
      FleetCheck.c6Harness,
    },
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
          ),
        FleetCheck.c6Harness => checkHarnessCanon(
            root: root,
            analysisOptionsOverrideRecorded:
                config.analysisOptionsOverrideRecorded,
            requiredCiFlutterVersion: config.requiredCiFlutterVersion,
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
