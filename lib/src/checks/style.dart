import 'dart:io';

import '../findings.dart';

const _check = 'C1-style';

/// The one canonical home of the design grammar; every app's
/// `openhearth_design` path dependency must point into it.
const _canonicalPathFragment = 'ohStyle/openhearth_design';

/// Where the Reckon-style vendored fork lives when an app has one.
const _forkDirRelPath = 'packages/openhearth_design';

/// Matches an 0xAARRGGBB literal — the form every design token takes.
final _hexLiteralPattern = RegExp(r'0x[0-9A-Fa-f]{8}');

/// C1 — the design grammar has ONE source of truth.
///
/// The app must depend on `openhearth_design` as a path dependency into the
/// canonical `ohStyle/openhearth_design` sibling. A path anywhere else is a
/// fork, and forks diverge silently: Reckon's vendored "reconstruction"
/// under `packages/openhearth_design` shipped hearth500 as 0xFFB85C38
/// against the canonical 0xFFA85040. A fork directory still on disk fails
/// independently of pubspec.yaml — fixing the dependency without deleting
/// the copy leaves the divergent source lying around to be re-imported.
List<ConformanceFinding> checkCanonicalDesignPackage({
  required Directory root,
}) {
  final findings = <ConformanceFinding>[];
  final pubspec = File('${root.path}/pubspec.yaml');
  if (!pubspec.existsSync()) {
    findings.add(ConformanceFinding(
      _check,
      'pubspec.yaml not found at the app root — cannot verify the '
      'openhearth_design dependency',
    ));
  } else {
    findings.addAll(_designDependencyFindings(pubspec.readAsStringSync()));
  }
  if (Directory('${root.path}/$_forkDirRelPath').existsSync()) {
    findings.add(ConformanceFinding(
      _check,
      '$_forkDirRelPath exists on disk — a vendored fork of the design '
      'package is present even if pubspec.yaml no longer points at it; '
      'delete it and depend on the canonical $_canonicalPathFragment sibling',
    ));
  }
  return findings;
}

final _designDepKeyPattern = RegExp(
  r'^(\s*)openhearth_design:[ \t]*(.*)$',
  multiLine: true,
);
final _pathValuePattern = RegExp(r'''path:\s*["']?([^"'\s#}]+)''');

List<ConformanceFinding> _designDependencyFindings(String pubspecYaml) {
  // EVERY occurrence of the key is examined — `dependency_overrides` is
  // what pub actually resolves, and firstMatch-only parsing never saw it.
  final keys = _designDepKeyPattern.allMatches(pubspecYaml).toList();
  if (keys.isEmpty) {
    return const [
      ConformanceFinding(
        _check,
        'no openhearth_design dependency in pubspec.yaml — the app must '
        'take its design grammar from the canonical package, not restate it',
      ),
    ];
  }
  return [
    for (final key in keys) ..._designDepOccurrenceFindings(pubspecYaml, key),
  ];
}

List<ConformanceFinding> _designDepOccurrenceFindings(
  String pubspecYaml,
  RegExpMatch key,
) {
  // The dependency's path lives either inline after the key
  // (`openhearth_design: {path: ...}`) or on a more-indented line below it.
  String? path;
  final inline = key.group(2)!;
  if (inline.isNotEmpty && !inline.startsWith('#')) {
    path = _pathValuePattern.firstMatch(inline)?.group(1);
  } else {
    final keyIndent = key.group(1)!.length;
    for (final line in pubspecYaml.substring(key.end).split('\n')) {
      if (line.trim().isEmpty) continue;
      // A '# path: ...' comment is not the path — skip comment lines
      // before both the dedent check and the value match.
      if (line.trimLeft().startsWith('#')) continue;
      if (line.length - line.trimLeft().length <= keyIndent) break;
      final match = _pathValuePattern.firstMatch(line);
      if (match != null) {
        path = match.group(1);
        break;
      }
    }
  }
  if (path == null) {
    return const [
      ConformanceFinding(
        _check,
        'openhearth_design is not a path dependency — it must be a path '
        'dependency on the canonical $_canonicalPathFragment sibling',
      ),
    ];
  }
  if (!path.contains(_canonicalPathFragment)) {
    return [
      ConformanceFinding(
        _check,
        "openhearth_design resolves to '$path' — a vendored fork, not the "
        'canonical $_canonicalPathFragment sibling; forks diverge silently '
        '(Reckon\'s did)',
      ),
    ];
  }
  return const [];
}

/// Every `Color(0xAARRGGBB)` value exported by the canonical design
/// package's `lib/src/colors.dart`, as ints, for
/// [checkNoRetypedTokenLiterals].
///
/// Throws [StateError] when colors.dart is missing: conformance must fail
/// loud when the canonical package cannot be found — an empty token set
/// would make the retyped-literal check pass vacuously against every app.
Set<int> canonicalTokenValuesFrom(Directory designPackageRoot) {
  final colors = File('${designPackageRoot.path}/lib/src/colors.dart');
  if (!colors.existsSync()) {
    throw StateError(
      'canonical design package colors.dart not found at ${colors.path} — '
      'refusing to run the retyped-token check against an empty token set',
    );
  }
  return _hexLiteralPattern
      .allMatches(colors.readAsStringSync())
      .map((m) => int.parse(m.group(0)!.substring(2), radix: 16))
      .toSet();
}

/// C1 — canonical token values may not be retyped as literals.
///
/// Scans `lib/**/*.dart` (generated `.g.dart` / `.freezed.dart` files are
/// build products, not authored code, and are skipped) for 0xAARRGGBB
/// literals whose value is in [canonicalTokenValues]: a retyped token
/// cannot follow a token change, so it must be imported from
/// openhearth_design instead. [allowed] records deliberate coincidences —
/// an app's own signature accent CAN equal a canonical token (Sundial's
/// sage 0xFF5E9478 IS OhColors.sage500) — via the app's FleetAppConfig.
List<ConformanceFinding> checkNoRetypedTokenLiterals({
  required Directory root,
  required Set<int> canonicalTokenValues,
  Set<int> allowed = const {},
}) {
  final lib = Directory('${root.path}/lib');
  if (!lib.existsSync()) return const [];
  final files = lib
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) =>
          f.path.endsWith('.dart') &&
          !f.path.endsWith('.g.dart') &&
          !f.path.endsWith('.freezed.dart'))
      .toList()
    // Directory order is platform-dependent; findings must not be.
    ..sort((a, b) => a.path.compareTo(b.path));

  final findings = <ConformanceFinding>[];
  for (final file in files) {
    final relative = file.path.substring(root.path.length + 1);
    final lines = file.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      for (final match in _hexLiteralPattern.allMatches(lines[i])) {
        final literal = match.group(0)!;
        final value = int.parse(literal.substring(2), radix: 16);
        if (!canonicalTokenValues.contains(value) || allowed.contains(value)) {
          continue;
        }
        findings.add(ConformanceFinding(
          _check,
          '$relative:${i + 1} retypes $literal, an exported design token — '
          'import it from openhearth_design instead of restating the hex, '
          'or record a deliberate coincidence in the app\'s FleetAppConfig',
        ));
      }
    }
  }
  return findings;
}
