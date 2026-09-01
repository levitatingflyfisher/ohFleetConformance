import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// C5 — the 320dp × large-text sweep, as a reusable template.
///
/// The fleet's recurring accessibility bug is a rigid Row overflowing at
/// large text scale on narrow screens — and it hides in screens (and
/// especially OPENED dialogs) that no golden covers. This helper pumps the
/// screen at a narrow phone viewport across the text scales and lets any
/// RenderFlex overflow surface as a normal test failure; it never swallows
/// exceptions.
///
/// [pumpScreen] must pump the full screen (usually via the app's real
/// theme/router harness). [interact] runs after each pump — use it to open
/// the dialogs and sheets the sweep must also cover; a closed dialog is
/// unswept surface.
Future<void> runA11ySweep(
  WidgetTester tester, {
  required Future<void> Function() pumpScreen,
  List<double> textScales = const [1.0, 3.0],
  Size logicalSize = const Size(320, 640),
  Future<void> Function()? interact,
}) async {
  tester.view.physicalSize = logicalSize;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAllTestValues);

  for (final scale in textScales) {
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    await pumpScreen();
    await tester.pumpAndSettle();
    if (interact != null) {
      await interact();
    }
  }
}

/// A viewport and the text scales to sweep it at.
class A11ySweepProfile {
  final Size logicalSize;
  final List<double> textScales;
  const A11ySweepProfile({required this.logicalSize, required this.textScales});

  /// C5's original sweep: the narrowest phone at the largest text — where
  /// rigid rows overflow.
  static const narrowLargeText = A11ySweepProfile(
    logicalSize: Size(320, 640),
    textScales: [1.0, 3.0],
  );

  /// The release gate for primary-action screens (roadmap item 24): the
  /// most common small Android width at a modest, common text boost.
  /// Reckon's onboarding could not be finished at 1.3×: both screens were
  /// a `Column` with a `Spacer` and no scroll view, so the only working
  /// control was clipped off the bottom (reckon audit finding 8). The
  /// profile asks that the primary action stay reachable, not just that
  /// nothing overflowed.
  static const primaryAction = A11ySweepProfile(
    logicalSize: Size(360, 640),
    textScales: [1.3],
  );
}

/// The sweep for a screen whose primary action must stay usable: it runs
/// the [A11ySweepProfile.primaryAction] profile (360dp × 1.3) and, at each
/// scale, requires [primaryAction] to be in the tree and hit-testable —
/// scrolling it into view first if a scrollable can — and then the
/// [A11ySweepProfile.narrowLargeText] overflow sweep (320dp × 3.0), with
/// [interact] run there to open dialogs.
///
/// A screen listed in `FleetAppConfig.primaryActionScreens` must be pumped
/// inside a `runPrimaryActionSweep(` call in `test/` (C5-primaryScreens
/// checks that statically; name the screen's constructor inside the call).
Future<void> runPrimaryActionSweep(
  WidgetTester tester, {
  required Future<void> Function() pumpScreen,
  required Finder primaryAction,
  Future<void> Function()? interact,
}) async {
  const profile = A11ySweepProfile.primaryAction;
  await runA11ySweep(
    tester,
    pumpScreen: pumpScreen,
    logicalSize: profile.logicalSize,
    textScales: profile.textScales,
    interact: () async {
      final scale = tester.platformDispatcher.textScaleFactor;
      final where = '${profile.logicalSize.width.toInt()}dp × $scale';
      expect(primaryAction, findsWidgets,
          reason: 'primary action is not on the screen at $where');
      if (primaryAction.hitTestable().evaluate().isEmpty) {
        await tester.ensureVisible(primaryAction.first);
        await tester.pumpAndSettle();
      }
      expect(primaryAction.hitTestable(), findsWidgets,
          reason: 'primary action cannot be reached (not tappable, and no '
              'scroll brings it into view) at $where');
    },
  );
  await runA11ySweep(
    tester,
    pumpScreen: pumpScreen,
    logicalSize: A11ySweepProfile.narrowLargeText.logicalSize,
    textScales: A11ySweepProfile.narrowLargeText.textScales,
    interact: interact,
  );
}
