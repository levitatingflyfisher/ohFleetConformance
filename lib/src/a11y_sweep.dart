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
