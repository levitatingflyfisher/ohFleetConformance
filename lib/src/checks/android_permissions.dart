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

  // A store listing is a promise made to someone who cannot read the
  // manifest. Eight apps tell F-Droid they ask for no network permission
  // at all; that sentence has to be falsifiable or it is marketing.
  findings.addAll(_listingClaimsMatchManifest(root));

  return findings;
}

List<ConformanceFinding> _mergedManifestFindings({
  required Directory root,
  required Set<String> allowlist,
}) {
  const check = 'C4-permissions';
  // Only release variants: debug/profile merged manifests are dev
  // scaffolding (and often stale, e.g. left over from before an
  // applicationId change) — the release surface is what ships. AGP has
  // used both a plural and a singular directory name across versions;
  // a check blind to either would silently skip the whole comparison
  // on half the fleet's toolchains.
  final mergedRoots = [
    Directory('${root.path}/build/app/intermediates/merged_manifests/release'),
    Directory('${root.path}/build/app/intermediates/merged_manifest/release'),
  ].where((d) => d.existsSync()).toList();
  // Absent build artifacts are not findings (C3's law): the comparison
  // bites only when a build has produced a merged manifest.
  if (mergedRoots.isEmpty) return const [];

  final manifests = <(Directory, File)>[
    for (final mergedRoot in mergedRoots)
      for (final f in mergedRoot.listSync(recursive: true).whereType<File>())
        if (f.path.endsWith('AndroidManifest.xml')) (mergedRoot, f),
  ]..sort((a, b) => a.$2.path.compareTo(b.$2.path));
  if (manifests.isEmpty) return const [];

  final findings = <ConformanceFinding>[];
  for (final (mergedRoot, manifest) in manifests) {
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

/// Findings where the published description claims a privacy property the
/// manifest contradicts.
///
/// Only the network claim is checked, because it is the one the fleet
/// actually makes and the one a reader most relies on. No listing is not a
/// finding — most apps have none.
List<ConformanceFinding> _listingClaimsMatchManifest(Directory root) {
  const check = 'C4-permissions';
  final listing = File('${root.path}/fastlane/metadata/android/en-US/'
      'full_description.txt');
  if (!listing.existsSync()) return const [];
  if (!listing.readAsStringSync().contains('no network permission')) {
    return const [];
  }

  final manifest =
      File('${root.path}/android/app/src/main/AndroidManifest.xml');
  if (!manifest.existsSync()) return const [];
  if (!manifest.readAsStringSync().contains('android.permission.INTERNET')) {
    return const [];
  }

  return [
    const ConformanceFinding(
      check,
      'the store listing claims this app asks for no network permission, '
      'but the source manifest declares android.permission.INTERNET — fix '
      'whichever one is wrong, because a stranger reading the listing '
      'cannot check it',
    ),
  ];
}

/// `<!-- ... -->`, including multi-line bodies: a commented-out permission
/// is not a declared permission.
final _xmlCommentPattern = RegExp(r'<!--.*?-->', dotAll: true);

/// Whole `<uses-permission …>` elements, so per-element attributes can be
/// inspected together.
final _usesPermissionElement = RegExp(r'<uses-permission\b[^>]*>');

/// `android:name` in single OR double quotes — both are valid XML.
final _namePattern = RegExp(
  'android:name\\s*=\\s*(?:"([^"]+)"|\'([^\']+)\')',
);

/// `tools:node="remove"` marks a merge-time STRIP of a plugin-injected
/// permission — the opposite of declaring it (the Peckish/RECORD_AUDIO
/// scenario). The strip's effect shows up in the merged-manifest check.
final _removeDirective = RegExp(
  'tools:node\\s*=\\s*(?:"remove"|\'remove\')',
);

Set<String> _usesPermissions(String manifestXml) {
  final visible = manifestXml.replaceAll(_xmlCommentPattern, '');
  final out = <String>{};
  for (final element in _usesPermissionElement.allMatches(visible)) {
    final tag = element.group(0)!;
    if (_removeDirective.hasMatch(tag)) continue;
    final name = _namePattern.firstMatch(tag);
    if (name != null) out.add((name.group(1) ?? name.group(2))!);
  }
  return out;
}
