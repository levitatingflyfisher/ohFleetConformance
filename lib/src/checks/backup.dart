import 'dart:io';

import '../findings.dart';

/// C2 — the app's backup adoption, as a failing-able test.
///
/// Enforcement layer for BACKUP_RETENTION_SPEC.md: the fleet once carried
/// nine hand-rolled divergent envelopes, and one shipped merge-restore app
/// (StillLife) whose confirm dialog claimed a destructive replace. Each
/// sub-check pins one of those regressions shut:
///
/// 1. pubspec.yaml depends on `sanctuary_backup_ui` (no hand-rolled backup).
/// 2. pubspec.lock, if present, pins it at >= [minimumPackageVersion] —
///    a lock still at 0.1.0 means the app never relocked after the
///    retention release. A missing lock is a fresh checkout, not a finding.
/// 3. Some serializer under lib/ implements `BackupSerializer`, uses the
///    shared `BackupEnvelope`, and offers `PreviewableBackupSerializer`
///    (preview-before-restore).
/// 4. If [mergeSemanticsRestore], the backup config overrides BOTH
///    `confirmTitle:` and `confirmActionLabel:` — the shared package's
///    destructive-default copy ('Replace all data?' / 'Replace everything')
///    lies for a merge restore.
/// 5. If [expectStartupMaintenance], some file calls
///    `runStartupMaintenance` (the vault freshness/prune hook). The flag
///    exists because PunctumTemporis drives the vault from its own service
///    in its own idiom.
List<ConformanceFinding> checkBackupConformance({
  required Directory root,
  required bool mergeSemanticsRestore,
  bool expectStartupMaintenance = true,
  String minimumPackageVersion = '0.2.0',
}) {
  const check = 'C2-backup';
  final findings = <ConformanceFinding>[];

  // 1. Declared dependency on the shared package.
  final pubspec = File('${root.path}/pubspec.yaml');
  if (!pubspec.existsSync() ||
      !_dependencyPattern.hasMatch(pubspec.readAsStringSync())) {
    findings.add(const ConformanceFinding(
      check,
      'pubspec.yaml does not depend on sanctuary_backup_ui — backup must go '
      'through the shared package, not a hand-rolled envelope',
    ));
  }

  // 2. Locked version, if the app has locked at all.
  final lock = File('${root.path}/pubspec.lock');
  if (lock.existsSync()) {
    final locked = _lockedVersion(lock.readAsStringSync());
    final minimum = _parseVersion(minimumPackageVersion);
    if (locked == null) {
      findings.add(ConformanceFinding(
        check,
        'pubspec.lock does not record a sanctuary_backup_ui version — '
        'run pub get so the lock pins >= $minimumPackageVersion',
      ));
    } else if (_parseVersion(locked) == null ||
        _compareVersions(_parseVersion(locked)!, minimum!) < 0) {
      findings.add(ConformanceFinding(
        check,
        'pubspec.lock pins sanctuary_backup_ui at $locked, below '
        '$minimumPackageVersion — the app never relocked after the '
        'retention release',
      ));
    }
  }

  // 3. Serializer conformance, scanned over lib/.
  final libSources = _dartSources(Directory('${root.path}/lib'));
  final serializers = libSources.entries
      .where((e) => _serializerClausePattern.hasMatch(e.value))
      .toList();
  if (serializers.isEmpty) {
    findings.add(const ConformanceFinding(
      check,
      'no class under lib/ implements BackupSerializer — the app has no '
      'conformant serializer',
    ));
  } else {
    if (!serializers.any((e) => e.value.contains('BackupEnvelope.'))) {
      findings.add(const ConformanceFinding(
        check,
        'no serializer references BackupEnvelope — the payload must be '
        'wrapped in the shared envelope, not a hand-rolled one',
      ));
    }
    if (!serializers
        .any((e) => e.value.contains('PreviewableBackupSerializer'))) {
      findings.add(const ConformanceFinding(
        check,
        'no serializer offers PreviewableBackupSerializer — restores must '
        'be previewable before they run',
      ));
    }
  }

  // 4. Merge-restore apps must override the destructive-default dialog copy.
  if (mergeSemanticsRestore) {
    for (final override in const ['confirmTitle:', 'confirmActionLabel:']) {
      if (!libSources.values.any((s) => s.contains(override))) {
        findings.add(ConformanceFinding(
          check,
          'merge-restore app never sets $override — the shared package\'s '
          "default copy ('Replace all data?' / 'Replace everything') lies "
          'about what the restore does',
        ));
      }
    }
  }

  // 5. The vault freshness/prune hook.
  if (expectStartupMaintenance &&
      !libSources.values.any((s) => s.contains('runStartupMaintenance'))) {
    findings.add(const ConformanceFinding(
      check,
      'no call to runStartupMaintenance under lib/ — the vault is never '
      'refreshed/pruned post-first-frame',
    ));
  }

  return findings;
}

/// A `sanctuary_backup_ui:` dependency key in pubspec.yaml, any form
/// (path / hosted / git all start the same line).
final _dependencyPattern =
    RegExp(r'^\s+sanctuary_backup_ui\s*:', multiLine: true);

/// An `implements`/`with`/`extends` clause naming `BackupSerializer`.
/// `[^{]*` keeps the match inside the clause and also accepts the
/// `PreviewableBackupSerializer` spelling.
final _serializerClausePattern =
    RegExp(r'(?:implements|extends|with)\s+[^{]*BackupSerializer');

/// Contents of every .dart file under [lib], keyed by path.
Map<String, String> _dartSources(Directory lib) {
  if (!lib.existsSync()) return const {};
  return {
    for (final f in lib.listSync(recursive: true).whereType<File>())
      if (f.path.endsWith('.dart')) f.path: f.readAsStringSync(),
  };
}

/// The `version: "x.y.z"` line inside the lock's `sanctuary_backup_ui:`
/// block — found by indentation so a neighbouring package's version can
/// never be picked up.
String? _lockedVersion(String lockYaml) {
  final lines = lockYaml.split('\n');
  final start = lines
      .indexWhere((l) => RegExp(r'^(\s*)sanctuary_backup_ui:\s*$').hasMatch(l));
  if (start == -1) return null;
  final blockIndent = lines[start].indexOf('s');
  for (var i = start + 1; i < lines.length; i++) {
    final line = lines[i];
    if (line.trim().isEmpty) continue;
    final indent = line.length - line.trimLeft().length;
    if (indent <= blockIndent) break; // left the block
    final version = RegExp(r'^version:\s*"([^"]+)"').firstMatch(line.trim());
    if (version != null) return version.group(1);
  }
  return null;
}

/// Numeric version components ("0.10.0" -> [0, 10, 0]); null if a
/// component isn't an integer. Pre-release/build suffixes are ignored.
List<int>? _parseVersion(String version) {
  final parts = version.split(RegExp(r'[-+]')).first.split('.');
  final components = <int>[];
  for (final part in parts) {
    final n = int.tryParse(part);
    if (n == null) return null;
    components.add(n);
  }
  return components;
}

/// Component-wise numeric compare (NOT lexical: 0.10.0 > 0.2.0); missing
/// components count as 0.
int _compareVersions(List<int> a, List<int> b) {
  final length = a.length > b.length ? a.length : b.length;
  for (var i = 0; i < length; i++) {
    final av = i < a.length ? a[i] : 0;
    final bv = i < b.length ? b[i] : 0;
    if (av != bv) return av.compareTo(bv);
  }
  return 0;
}
