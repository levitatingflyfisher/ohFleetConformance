import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oh_fleet_conformance/oh_fleet_conformance.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('ohfc_perm_');
  });

  tearDown(() {
    root.deleteSync(recursive: true);
  });

  void writeManifest(String body, {String variant = 'main'}) {
    final file =
        File('${root.path}/android/app/src/$variant/AndroidManifest.xml');
    file.createSync(recursive: true);
    file.writeAsStringSync(body);
  }

  const notifications = 'android.permission.POST_NOTIFICATIONS';
  const vibrate = 'android.permission.VIBRATE';
  const internet = 'android.permission.INTERNET';

  String manifestWith(List<String> permissions) => '''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
${permissions.map((p) => '    <uses-permission android:name="$p" />').join('\n')}
    <application android:label="fixture"></application>
</manifest>
''';

  test('manifest matching the allowlist yields no findings', () {
    writeManifest(manifestWith([notifications, vibrate]));
    final findings = checkAndroidPermissions(
      root: root,
      allowlist: {notifications, vibrate},
    );
    expect(findings, isEmpty);
  });

  test('zero-permission manifest with empty allowlist passes', () {
    writeManifest(manifestWith([]));
    expect(
      checkAndroidPermissions(root: root, allowlist: {}),
      isEmpty,
    );
  });

  test('a declared permission missing from the allowlist is a finding', () {
    // The Furrow scenario: someone adds INTERNET to a no-network app.
    writeManifest(manifestWith([notifications, internet]));
    final findings = checkAndroidPermissions(
      root: root,
      allowlist: {notifications},
    );
    expect(findings, hasLength(1));
    expect(findings.single.message, contains(internet));
    expect(findings.single.message, contains('not in the allowlist'));
  });

  test('an allowlisted permission absent from the manifest is a finding', () {
    // Drift in the other direction: the recorded claim no longer matches.
    writeManifest(manifestWith([]));
    final findings = checkAndroidPermissions(
      root: root,
      allowlist: {vibrate},
    );
    expect(findings, hasLength(1));
    expect(findings.single.message, contains(vibrate));
    expect(findings.single.message, contains('allowlisted but not declared'));
  });

  test('debug and profile manifests are ignored', () {
    // Flutter's dev-only manifests always declare INTERNET; that must not
    // fail a no-INTERNET app.
    writeManifest(manifestWith([]));
    writeManifest(manifestWith([internet]), variant: 'debug');
    writeManifest(manifestWith([internet]), variant: 'profile');
    expect(
      checkAndroidPermissions(root: root, allowlist: {}),
      isEmpty,
    );
  });

  test('missing main manifest is itself a finding', () {
    final findings = checkAndroidPermissions(root: root, allowlist: {});
    expect(findings, hasLength(1));
    expect(findings.single.message, contains('AndroidManifest.xml'));
  });

  test('a commented-out uses-permission is not declared', () {
    writeManifest('''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <!-- <uses-permission android:name="$internet" /> -->
    <application android:label="fixture"></application>
</manifest>
''');
    expect(
      checkAndroidPermissions(root: root, allowlist: {}),
      isEmpty,
    );
  });

  test('a multi-line comment hiding a uses-permission is not declared', () {
    writeManifest('''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <!--
      dev-only, disabled:
      <uses-permission android:name="$internet" />
    -->
    <uses-permission android:name="$notifications" />
    <application android:label="fixture"></application>
</manifest>
''');
    expect(
      checkAndroidPermissions(root: root, allowlist: {notifications}),
      isEmpty,
    );
  });

  test('single-quoted android:name attributes are recognized', () {
    writeManifest('''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name='$vibrate' />
    <application android:label="fixture"></application>
</manifest>
''');
    expect(
      checkAndroidPermissions(root: root, allowlist: {vibrate}),
      isEmpty,
    );
  });

  group('merged-manifest deepening (C4 v2)', () {
    const wakeLock = 'android.permission.WAKE_LOCK';
    const networkState = 'android.permission.ACCESS_NETWORK_STATE';

    void writeMergedManifest(List<String> permissions,
        {String abi = 'arm64-v8a'}) {
      final file = File(
        '${root.path}/build/app/intermediates/merged_manifests/release/'
        'processReleaseManifest/$abi/AndroidManifest.xml',
      );
      file.createSync(recursive: true);
      file.writeAsStringSync(manifestWith(permissions));
    }

    test('a plugin-injected permission not in the merged allowlist is a finding',
        () {
      writeManifest(manifestWith([notifications]));
      writeMergedManifest([notifications, wakeLock, internet]);
      final findings = checkAndroidPermissions(
        root: root,
        allowlist: {notifications},
        mergedAllowlist: {notifications, wakeLock},
      );
      expect(findings, hasLength(1));
      expect(findings.single.message, contains(internet));
      expect(findings.single.message, contains('merged'));
    });

    test('an allowlisted merged permission that disappeared is a finding', () {
      writeManifest(manifestWith([notifications]));
      writeMergedManifest([notifications, wakeLock]);
      final findings = checkAndroidPermissions(
        root: root,
        allowlist: {notifications},
        mergedAllowlist: {notifications, wakeLock, networkState},
      );
      expect(findings, hasLength(1));
      expect(findings.single.message, contains(networkState));
    });

    test('a matching merged surface yields no findings', () {
      writeManifest(manifestWith([notifications]));
      writeMergedManifest([notifications, wakeLock, networkState]);
      expect(
        checkAndroidPermissions(
          root: root,
          allowlist: {notifications},
          mergedAllowlist: {notifications, wakeLock, networkState},
        ),
        isEmpty,
      );
    });

    test('every ABI variant found on disk is checked', () {
      writeManifest(manifestWith([notifications]));
      writeMergedManifest([notifications]);
      writeMergedManifest([notifications, internet], abi: 'armeabi-v7a');
      final findings = checkAndroidPermissions(
        root: root,
        allowlist: {notifications},
        mergedAllowlist: {notifications},
      );
      expect(findings, hasLength(1));
      expect(findings.single.message, contains(internet));
    });

    test('no merged artifact on disk skips the merged comparison — a plain '
        'flutter test run without a build must pass', () {
      writeManifest(manifestWith([notifications]));
      expect(
        checkAndroidPermissions(
          root: root,
          allowlist: {notifications},
          mergedAllowlist: {notifications, wakeLock},
        ),
        isEmpty,
      );
    });

    test('a null merged allowlist keeps the merged check off even when the '
        'artifact exists — apps opt in by recording their surface', () {
      writeManifest(manifestWith([notifications]));
      writeMergedManifest([notifications, wakeLock, internet]);
      expect(
        checkAndroidPermissions(root: root, allowlist: {notifications}),
        isEmpty,
      );
    });
  });
}
