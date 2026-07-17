import 'dart:io';

import '../findings.dart';

/// C4 — the app's Android permission surface, as a failing-able test.
///
/// Compares the `<uses-permission>` set in the MAIN AndroidManifest.xml
/// (debug/profile manifests are Flutter dev scaffolding and deliberately
/// ignored) against the app's recorded allowlist, in BOTH directions:
/// a permission added without updating the allowlist fails (the
/// Furrow-gains-INTERNET scenario), and an allowlisted permission that
/// disappears fails too (the claim in the allowlist has drifted).
List<ConformanceFinding> checkAndroidPermissions({
  required Directory root,
  required Set<String> allowlist,
}) {
  const check = 'C4-permissions';
  final manifest =
      File('${root.path}/android/app/src/main/AndroidManifest.xml');
  if (!manifest.existsSync()) {
    return [
      ConformanceFinding(
        check,
        'main AndroidManifest.xml not found at '
        'android/app/src/main/AndroidManifest.xml — cannot verify the '
        'permission surface',
      ),
    ];
  }

  final declared = _usesPermissions(manifest.readAsStringSync());
  final findings = <ConformanceFinding>[];
  for (final permission in declared.difference(allowlist)) {
    findings.add(ConformanceFinding(
      check,
      'manifest declares $permission which is not in the allowlist — '
      'either remove it or record the deliberate decision in the app\'s '
      'FleetAppConfig',
    ));
  }
  for (final permission in allowlist.difference(declared)) {
    findings.add(ConformanceFinding(
      check,
      '$permission is allowlisted but not declared in the manifest — '
      'the recorded permission surface has drifted; update the allowlist',
    ));
  }
  return findings;
}

final _usesPermissionPattern = RegExp(
  r'<uses-permission[^>]*android:name\s*=\s*"([^"]+)"',
);

Set<String> _usesPermissions(String manifestXml) => _usesPermissionPattern
    .allMatches(manifestXml)
    .map((m) => m.group(1)!)
    .toSet();
