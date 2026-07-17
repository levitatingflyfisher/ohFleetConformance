/// OpenHearth fleet conformance suite.
///
/// Every fleet standard lands here as a check that can FAIL, never as a
/// document that drifts. Apps instantiate the suite in one file
/// (`test/fleet_conformance_test.dart`) with their [FleetAppConfig].
library;

export 'src/a11y_sweep.dart';
export 'src/canonical_templates.dart';
export 'src/checks/android_permissions.dart';
export 'src/checks/backup.dart';
export 'src/checks/budgets.dart';
export 'src/checks/harness.dart';
export 'src/checks/style.dart';
export 'src/findings.dart';
export 'src/fleet_conformance.dart';
