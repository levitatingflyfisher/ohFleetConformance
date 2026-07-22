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
  write('budgets.json', jsonEncode({
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
      expect(results.keys.toSet(), FleetCheck.values.toSet());
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

    test('violations land under their own check keys', () {
      // Retype a canonical token in app code + sneak INTERNET into the
      // manifest: C1 and C4 must each report, independently.
      File('${app.path}/lib/theme.dart').writeAsStringSync(
          'const kAccent = Color(0xFFA85040);\n');
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
      File('${app.path}/lib/theme.dart').writeAsStringSync(
          'const kSignature = Color(0xFF5E9478);\n');
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
