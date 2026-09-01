import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oh_fleet_conformance/oh_fleet_conformance.dart';

/// Builds a fully conformant fixture app at <parent>/app with the canonical
/// design package at <parent>/ohStyle/openhearth_design — the layout the
/// real fleet uses, so the default relative designPackagePath resolves.
Directory buildConformantFixture(Directory parent) {
  final app = Directory('${parent.path}/app')..createSync(recursive: true);

  void write(String relative, String content) {
    File('${app.path}/$relative')
      ..createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  File('${parent.path}/ohStyle/openhearth_design/lib/src/colors.dart')
    ..createSync(recursive: true)
    ..writeAsStringSync('''
class OhColors {
  static const hearth500 = Color(0xFFA85040);
  static const sage500 = Color(0xFF5E9478);
}
''');

  // Generated sources are ignored, never committed (C6).
  write('.gitignore', 'build/\n*.g.dart\n');

  write('pubspec.yaml', '''
name: fixture_app
dependencies:
  openhearth_design:
    path: ../ohStyle/openhearth_design
  sanctuary_backup_ui:
    path: ../packages/sanctuary_backup_ui
''');
  write('pubspec.lock', '''
packages:
  sanctuary_backup_ui:
    dependency: "direct main"
    source: path
    version: "0.2.0"
''');
  // Real-looking call sites, deliberately NOT comments: the checks scan
  // comment-stripped source, so only real code may satisfy them.
  write('lib/backup/serializer.dart', '''
class FixtureSerializer implements BackupSerializer, PreviewableBackupSerializer {
  String serialize(String data) => BackupEnvelope.wrap(data);
  String preview(String raw) => BackupEnvelope.unwrap(raw);
}
''');
  write('lib/main.dart', '''
void main() {
  runStartupMaintenance();
}
''');
  write(
      'budgets.json',
      jsonEncode({
        'main_dart_js_gz_max_bytes': 1400000,
        'apk_arm64_max_bytes': 26000000,
      }));
  write('android/app/src/main/AndroidManifest.xml', '''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
    <application android:label="fixture"></application>
</manifest>
''');
  write('test/flutter_test_config.dart', canonicalFlutterTestConfig);
  write('analysis_options.yaml', canonicalAnalysisOptions);
  write('.github/workflows/ci.yml', '''
jobs:
  test:
    steps:
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.38.7'
''');
  return app;
}

const fixtureConfig = FleetAppConfig(
  appId: 'fixture',
  styleTier: StyleTier.tokens,
  androidPermissions: {'android.permission.POST_NOTIFICATIONS'},
);

void main() {
  group('collectFleetFindings', () {
    late Directory parent;
    late Directory app;

    setUp(() {
      parent = Directory.systemTemp.createTempSync('ohfc_runner_');
      app = buildConformantFixture(parent);
    });

    tearDown(() => parent.deleteSync(recursive: true));

    test('conformant fixture yields every enabled check with zero findings',
        () {
      final results = collectFleetFindings(fixtureConfig, root: app);
      // Every ENABLED check gets an entry — not every check that exists.
      // C7 ships outside the default set, so the two are no longer equal.
      expect(results.keys.toSet(), fixtureConfig.checks);
      for (final entry in results.entries) {
        expect(entry.value, isEmpty,
            reason: '${entry.key}: ${entry.value.join('; ')}');
      }
    });

    test('only the configured subset of checks is evaluated', () {
      final results = collectFleetFindings(
        const FleetAppConfig(
          appId: 'fixture',
          styleTier: StyleTier.tokens,
          androidPermissions: {'android.permission.POST_NOTIFICATIONS'},
          checks: {FleetCheck.c4Permissions},
        ),
        root: app,
      );
      expect(results.keys.toSet(), {FleetCheck.c4Permissions});
    });

    test(
        'c8IconButtons is wired to the icon-button check, not silently to '
        'a different one', () {
      // A wrong entry in the switch would still compile and could still
      // report SOMETHING for this key — checking only "is not empty" would
      // pass even if c8IconButtons had been pointed at, say, C7's fonts
      // check. The label and the message content both belong to the icon
      // button check specifically, so a mis-wire fails here on both.
      File('${app.path}/lib/theme.dart').writeAsStringSync(
          'final x = IconButton.filled(onPressed: (){}, icon: const Icon(0));\n');
      final results = collectFleetFindings(
        const FleetAppConfig(
          appId: 'fixture',
          styleTier: StyleTier.tokens,
          androidPermissions: {'android.permission.POST_NOTIFICATIONS'},
          checks: {FleetCheck.c8IconButtons},
        ),
        root: app,
      );
      expect(results.keys.toSet(), {FleetCheck.c8IconButtons});
      final findings = results[FleetCheck.c8IconButtons]!;
      expect(findings, hasLength(1));
      expect(findings.single.check, 'C8-iconButtons');
      expect(findings.single.message, contains('IconButton.filled('));
    });

    test('the 0.8.0 checks ship outside the default set', () {
      // Every app consumes this package by path: a new check in
      // defaultChecks would turn red everywhere the instant it landed.
      for (final check in [
        FleetCheck.c9Routes,
        FleetCheck.c10RawErrors,
        FleetCheck.c11IconLabels,
        FleetCheck.c11StrictBarLabels,
        FleetCheck.c12AccentVsError,
        FleetCheck.c5PrimaryScreens,
      ]) {
        expect(FleetAppConfig.defaultChecks, isNot(contains(check)));
      }
    });

    test('c9Routes is wired to the route check and receives exemptions', () {
      File('${app.path}/lib/router.dart').writeAsStringSync('''
final router = GoRouter(routes: [
  GoRoute(path: '/', builder: (c, s) => const Home()),
  GoRoute(path: '/orphan', builder: (c, s) => const Orphan()),
]);
''');
      FleetAppConfig config(Map<String, String> exemptions) => FleetAppConfig(
            appId: 'fixture',
            styleTier: StyleTier.tokens,
            androidPermissions: const {},
            checks: const {FleetCheck.c9Routes},
            routeExemptions: exemptions,
          );
      final findings =
          collectFleetFindings(config(const {}), root: app)[FleetCheck.c9Routes]!;
      expect(findings.single.check, 'C9-routes');
      expect(findings.single.message, contains("'/orphan'"));
      expect(
          collectFleetFindings(config(const {'/orphan': 'deep link only'}),
              root: app)[FleetCheck.c9Routes],
          isEmpty);
    });

    test('c10RawErrors is wired to the raw-error check', () {
      File('${app.path}/lib/screen.dart').writeAsStringSync(
          "Widget f(error) => Text('Error: \$error');\n");
      final findings = collectFleetFindings(
        const FleetAppConfig(
          appId: 'fixture',
          styleTier: StyleTier.tokens,
          androidPermissions: {},
          checks: {FleetCheck.c10RawErrors},
        ),
        root: app,
      )[FleetCheck.c10RawErrors]!;
      expect(findings.single.check, 'C10-rawErrors');
      expect(findings.single.message, contains('lib/screen.dart:1'));
    });

    test('c11IconLabels is wired to the app-bar label check', () {
      File('${app.path}/lib/bar.dart').writeAsStringSync(
          'Widget b() => AppBar(actions: [\n'
          '  IconButton(icon: const Icon(Icons.a), onPressed: () {}),\n'
          ']);\n');
      final findings = collectFleetFindings(
        const FleetAppConfig(
          appId: 'fixture',
          styleTier: StyleTier.tokens,
          androidPermissions: {},
          checks: {FleetCheck.c11IconLabels},
        ),
        root: app,
      )[FleetCheck.c11IconLabels]!;
      expect(findings.single.check, 'C11-iconLabels');
      expect(findings.single.message, contains('lib/bar.dart:2'));
    });

    test('c11StrictBarLabels is wired to the strict label check', () {
      File('${app.path}/lib/bar.dart').writeAsStringSync(
          'Widget b() => AppBar(actions: [\n'
          "  IconButton(tooltip: 'Filter', icon: const Icon(Icons.a), "
          'onPressed: () {}),\n'
          ']);\n');
      FleetAppConfig config(FleetCheck check) => FleetAppConfig(
            appId: 'fixture',
            styleTier: StyleTier.tokens,
            androidPermissions: const {},
            checks: {check},
          );
      expect(
          collectFleetFindings(config(FleetCheck.c11IconLabels),
              root: app)[FleetCheck.c11IconLabels],
          isEmpty);
      final findings = collectFleetFindings(
          config(FleetCheck.c11StrictBarLabels),
          root: app)[FleetCheck.c11StrictBarLabels]!;
      expect(findings.single.check, 'C11-strictBarLabels');
      expect(findings.single.message, contains('lib/bar.dart:2'));
    });

    test('c11StrictBarLabels receives the bar-label exemptions', () {
      File('${app.path}/lib/bar.dart').writeAsStringSync(
          'Widget b() => AppBar(actions: [\n'
          "  PopupMenuButton<int>(key: const Key('pick'), "
          'itemBuilder: (c) => const [], child: Face()),\n'
          ']);\n');
      FleetAppConfig config(Map<String, String> ex) => FleetAppConfig(
            appId: 'fixture',
            styleTier: StyleTier.tokens,
            androidPermissions: const {},
            checks: const {FleetCheck.c11StrictBarLabels},
            barLabelExemptions: ex,
          );
      expect(
          collectFleetFindings(config(const {}),
              root: app)[FleetCheck.c11StrictBarLabels],
          hasLength(1));
      expect(
          collectFleetFindings(
              config(const {'lib/bar.dart#pick': 'Face shows the word'}),
              root: app)[FleetCheck.c11StrictBarLabels],
          isEmpty);
    });

    test('c12AccentVsError is wired, reads the design package and the '
        'declared accents', () {
      // The fixture's canonical package has colors.dart but no roles:
      // the check must say so, not pass.
      FleetAppConfig config(List<FleetAccent> accents) => FleetAppConfig(
            appId: 'fixture',
            styleTier: StyleTier.tokens,
            androidPermissions: const {},
            checks: const {FleetCheck.c12AccentVsError},
            accentColors: accents,
          );
      var findings = collectFleetFindings(config(const []),
          root: app)[FleetCheck.c12AccentVsError]!;
      expect(findings.single.check, 'C12-accentVsError');
      expect(findings.single.message, contains('urgency'));

      File('${parent.path}/ohStyle/openhearth_design/lib/src/colors.dart')
          .writeAsStringSync('''
class OhColors {
  static const hearth500 = Color(0xFFA85040);
  static const sage500 = Color(0xFF5E9478);
  static const red500 = Color(0xFF9B1D29);
}
''');
      File('${parent.path}/ohStyle/openhearth_design/lib/src/color_roles.dart')
          .writeAsStringSync('''
class OhColorRoles {
  static const light = OhColorRoles(urgency: OhColors.red500);
}
''');
      findings = collectFleetFindings(
          config(const [FleetAccent.light(0xFFA0202C)]),
          root: app)[FleetCheck.c12AccentVsError]!;
      expect(findings, isNotEmpty);
      expect(findings.first.message, contains('0xFFA0202C'));
      expect(
          collectFleetFindings(config(const [FleetAccent.light(0xFF3D82C9)]),
              root: app)[FleetCheck.c12AccentVsError],
          isEmpty);
    });

    test('c5PrimaryScreens is wired and receives the screen list', () {
      File('${app.path}/lib/today.dart')
          .writeAsStringSync('class TodayScreen {}\n');
      final findings = collectFleetFindings(
        const FleetAppConfig(
          appId: 'fixture',
          styleTier: StyleTier.tokens,
          androidPermissions: {},
          checks: {FleetCheck.c5PrimaryScreens},
          primaryActionScreens: {'TodayScreen'},
        ),
        root: app,
      )[FleetCheck.c5PrimaryScreens]!;
      expect(findings.single.check, 'C5-primaryScreens');
      expect(findings.single.message, contains('TodayScreen'));
    });

    test('violations land under their own check keys', () {
      // Retype a canonical token in app code + sneak INTERNET into the
      // manifest: C1 and C4 must each report, independently.
      File('${app.path}/lib/theme.dart')
          .writeAsStringSync('const kAccent = Color(0xFFA85040);\n');
      File('${app.path}/android/app/src/main/AndroidManifest.xml')
          .writeAsStringSync('''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
    <uses-permission android:name="android.permission.INTERNET" />
    <application android:label="fixture"></application>
</manifest>
''');
      final results = collectFleetFindings(fixtureConfig, root: app);
      expect(results[FleetCheck.c1Style], isNotEmpty);
      expect(results[FleetCheck.c4Permissions], isNotEmpty);
      expect(results[FleetCheck.c2Backup], isEmpty);
    });

    test('allowedTokenLiterals suppresses the C1 retype finding', () {
      File('${app.path}/lib/theme.dart')
          .writeAsStringSync('const kSignature = Color(0xFF5E9478);\n');
      final results = collectFleetFindings(
        const FleetAppConfig(
          appId: 'fixture',
          styleTier: StyleTier.tokens,
          androidPermissions: {'android.permission.POST_NOTIFICATIONS'},
          allowedTokenLiterals: {0xFF5E9478},
        ),
        root: app,
      );
      expect(results[FleetCheck.c1Style], isEmpty);
    });

    test('merge-semantics flag propagates to C2', () {
      final results = collectFleetFindings(
        const FleetAppConfig(
          appId: 'fixture',
          styleTier: StyleTier.tokens,
          androidPermissions: {'android.permission.POST_NOTIFICATIONS'},
          mergeSemanticsRestore: true,
        ),
        root: app,
      );
      // The fixture never overrides the confirm copy, so a merge app
      // must be flagged twice (title + action label).
      expect(results[FleetCheck.c2Backup], hasLength(2));
    });

    test('a missing design package becomes a C1 finding, not a crash', () {
      Directory('${parent.path}/ohStyle').deleteSync(recursive: true);
      final results = collectFleetFindings(fixtureConfig, root: app);
      expect(results[FleetCheck.c1Style], isNotEmpty);
      expect(
        results[FleetCheck.c1Style]!.map((f) => f.message).join(),
        contains('colors.dart'),
      );
    });

    test('a check that throws becomes a finding for that check only', () {
      // An unreadable lib file (invalid UTF-8) makes the source-scanning
      // checks throw on read. That must surface as findings on THOSE
      // checks — never crash the whole map or taint unrelated checks.
      File('${app.path}/lib/garbage.dart')
          .writeAsBytesSync([0xC3, 0x28, 0xFF, 0x00]);
      final results = collectFleetFindings(fixtureConfig, root: app);
      // Every ENABLED check gets an entry — not every check that exists.
      // C7 ships outside the default set, so the two are no longer equal.
      expect(results.keys.toSet(), fixtureConfig.checks);
      expect(results[FleetCheck.c1Style], isNotEmpty); // reads lib sources
      expect(results[FleetCheck.c2Backup], isNotEmpty); // reads lib sources
      expect(results[FleetCheck.c3Budgets], isEmpty);
      expect(results[FleetCheck.c4Permissions], isEmpty);
      expect(results[FleetCheck.c6Harness], isEmpty);
    });
  });

  group('runFleetConformance evaluates the checks once per suite', () {
    final memoParent = Directory.systemTemp.createTempSync('ohfc_memo_');
    final memoApp = buildConformantFixture(memoParent);
    var testsSeen = 0;
    setUp(() {
      testsSeen++;
      if (testsSeen > 1 && memoParent.existsSync()) {
        // Destroy the fixture after the first check test has run: with one
        // shared (memoized) evaluation the remaining checks must still
        // pass; re-running the filesystem work per test would now find a
        // gutted app and fail every one of them.
        memoParent.deleteSync(recursive: true);
      }
    });
    tearDownAll(() {
      if (memoParent.existsSync()) memoParent.deleteSync(recursive: true);
    });
    runFleetConformance(fixtureConfig, root: memoApp);
  });

  // Integration: the wrapper registered below runs the real checks as real
  // tests against a persistent conformant fixture — if the wrapper or any
  // check regresses, the suite fails here without any app involved.
  final integrationParent =
      Directory.systemTemp.createTempSync('ohfc_runner_live_');
  final integrationApp = buildConformantFixture(integrationParent);
  tearDownAll(() => integrationParent.deleteSync(recursive: true));
  runFleetConformance(fixtureConfig, root: integrationApp);
}
