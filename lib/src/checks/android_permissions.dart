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
///
/// v2 deepening: when [mergedAllowlist] is recorded AND a MERGED manifest
/// artifact exists under build/ (present after an APK build on the dev box;
/// a plain `flutter test` run must pass without one), the merged
/// `<uses-permission>` set — which includes plugin-injected permissions the
/// source manifest never shows — is compared the same both-direction way.
/// Every ABI variant found is checked: a permission smuggled into one split
/// is still a finding.
List<ConformanceFinding> checkAndroidPermissions({
  required Directory root,
  required Set<String> allowlist,
  Set<String>? mergedAllowlist,
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

  if (mergedAllowlist != null) {
    findings.addAll(
      _mergedManifestFindings(root: root, allowlist: mergedAllowlist),
    );
  }
  return findings;
}

List<ConformanceFinding> _mergedManifestFindings({
  required Directory root,
  required Set<String> allowlist,
}) {
  const check = 'C4-permissions';
  final mergedRoot =
      Directory('${root.path}/build/app/intermediates/merged_manifests');
  // Absent build artifacts are not findings (C3's law): the comparison
  // bites only when a build has produced a merged manifest.
  if (!mergedRoot.existsSync()) return const [];

  final manifests = mergedRoot
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('AndroidManifest.xml'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  if (manifests.isEmpty) return const [];

  final findings = <ConformanceFinding>[];
  for (final manifest in manifests) {
    final variant = manifest.path
        .substring(mergedRoot.path.length + 1)
        .replaceAll('/AndroidManifest.xml', '');
    final declared = _usesPermissions(manifest.readAsStringSync());
    for (final permission in declared.difference(allowlist)) {
      findings.add(ConformanceFinding(
        check,
        'merged manifest ($variant) carries $permission which is not in the '
        'merged allowlist — a plugin or manifest merge injected it; either '
        'drop the dependency behavior or record the deliberate decision',
      ));
    }
    for (final permission in allowlist.difference(declared)) {
      findings.add(ConformanceFinding(
        check,
        '$permission is in the merged allowlist but absent from the merged '
        'manifest ($variant) — the recorded surface has drifted; update '
        'the allowlist',
      ));
    }
  }
  return findings;
}

/// `<!-- ... -->`, including multi-line bodies: a commented-out permission
/// is not a declared permission.
final _xmlCommentPattern = RegExp(r'<!--.*?-->', dotAll: true);

/// `android:name` in single OR double quotes — both are valid XML.
final _usesPermissionPattern = RegExp(
  '<uses-permission[^>]*android:name\\s*=\\s*(?:"([^"]+)"|\'([^\']+)\')',
);

Set<String> _usesPermissions(String manifestXml) => _usesPermissionPattern
    .allMatches(manifestXml.replaceAll(_xmlCommentPattern, ''))
    .map((m) => (m.group(1) ?? m.group(2))!)
    .toSet();
