import 'dart:io';

import '../findings.dart';
import '../source_scan.dart';

const _check = 'C5-primaryScreens';

/// C5-primaryScreens — every screen the app names as a primary-action
/// screen is actually swept at 360dp × 1.3 (roadmap item 24).
///
/// The profile lives in `runPrimaryActionSweep` (a11y_sweep.dart); this
/// check is what stops the list in `FleetAppConfig.primaryActionScreens`
/// from being a wish. For each listed widget class:
///  * the class must exist in authored `lib/` code (a renamed or deleted
///    screen is a stale entry, not a pass);
///  * some `runPrimaryActionSweep(` call under `test/` must name the class
///    INSIDE its argument list — a file that pumps the screen in one test
///    and sweeps something else in another does not count, and neither
///    does the older 320dp-only `runA11ySweep`.
///
/// Limits: the check proves the sweep is WRITTEN, not that it passes (the
/// test itself does that when it runs). A sweep that reaches the screen
/// through a helper (`pumpOnboarding()`) will not be seen — name the
/// constructor in the call.
///
/// Cannot pass by finding nothing: an empty list is a finding.
List<ConformanceFinding> checkPrimaryScreenSweeps({
  required Directory root,
  required Set<String> screens,
}) {
  if (screens.isEmpty) {
    return const [
      ConformanceFinding(
        _check,
        'FleetAppConfig.primaryActionScreens is empty — list the screens '
        'whose primary action must survive 360dp × 1.3 (onboarding, the '
        'main add/log screen) or do not enable this check',
      ),
    ];
  }

  final lib = ScannedSource.under(root);
  final tests = ScannedSource.under(root, 'test');
  final sweptSpans = <String>[
    for (final t in tests)
      for (final (open, close) in t.calls('runPrimaryActionSweep'))
        t.structure.substring(open, close),
  ];

  final findings = <ConformanceFinding>[];
  for (final name in screens.toList()..sort()) {
    final n = RegExp.escape(name);
    final declared =
        lib.any((s) => RegExp('\\bclass\\s+$n\\b').hasMatch(s.structure));
    if (!declared) {
      findings.add(ConformanceFinding(
        _check,
        "primaryActionScreens lists '$name', but no class $name exists "
        'under lib/ — a stale entry; update or remove it',
      ));
      continue;
    }
    final swept = sweptSpans
        .any((span) => RegExp('(?<![A-Za-z0-9_])$n\\b').hasMatch(span));
    if (!swept) {
      findings.add(ConformanceFinding(
        _check,
        '$name is a primary-action screen but no runPrimaryActionSweep( '
        'call under test/ pumps it — add one (360dp × 1.3 with its primary '
        'action reachable, plus 320dp × 3.0), naming $name inside the call',
      ));
    }
  }
  return findings;
}
