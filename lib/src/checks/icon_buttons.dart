import 'dart:io';

import '../dart_source.dart';
import '../findings.dart';

const _check = 'C8-iconButtons';

/// C8 — an app on `openhearth_design`'s theme may not construct a bare
/// `IconButton.filled`/`IconButton.filledTonal`.
///
/// ohStyle's `OhTheme` sets an app-wide `ThemeData.iconTheme` color of
/// `primary`. In Flutter 3.38.7 that ambient color is injected ABOVE
/// `IconButton`'s own variant defaults, so a bare `IconButton.filled` paints
/// its glyph in `primary` — the exact color of its own fill. The button is
/// there, tappable, and invisible; a device tester reported it as "blank
/// circles". `IconButton.filledTonal` collides the same way, landing
/// `primary` where `onSecondaryContainer` belongs — poor contrast rather
/// than invisibility, but the same root cause.
///
/// `OhIconButton.filled`/`OhIconButton.filledTonal` in `openhearth_design`
/// pin the correct foreground per variant; this check is what stops the
/// next `IconButton.filled(` from re-opening the collision with a green
/// test suite sitting on top of it.
///
/// Two scoping decisions, both deliberate:
///
///  * **`lib/` only — never `test/`.** A regression test that PROVES the
///    theme collision exists must be free to construct a bare
///    `IconButton.filled`; flagging it would flag the very test that
///    guards against the bug returning. Do not widen the scope to `test/`.
///  * **Gated on the `openhearth_design` dependency.** An app whose
///    pubspec never depends on `openhearth_design` never gets the
///    app-wide `iconTheme` collision in the first place — flagging it
///    would be a false positive against a theme this check knows nothing
///    about. The gate is read straight off pubspec.yaml, not off whether
///    the check happens to be enabled for the app.
///
/// C8 ships OUTSIDE `FleetAppConfig.defaultChecks`, exactly like C7 — every
/// app consumes this package by path, so adding to the default set would
/// turn the rule on everywhere the instant this file changed. Apps opt in
/// via `checks:` once they have adopted `OhIconButton`.
List<ConformanceFinding> checkNoBareIconButtonVariants({
  required Directory root,
}) {
  if (!_dependsOnOpenhearthDesign(root)) return const [];

  final lib = Directory('${root.path}/lib');
  final files = lib.existsSync()
      ? lib
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) =>
              f.path.endsWith('.dart') &&
              !f.path.endsWith('.g.dart') &&
              !f.path.endsWith('.freezed.dart'))
          .toList()
      : <File>[];
  // Directory order is platform-dependent; findings must not be.
  files.sort((a, b) => a.path.compareTo(b.path));

  if (files.isEmpty) {
    return const [
      ConformanceFinding(
        _check,
        'no Dart sources found under lib/ — nothing was swept, which is '
        'not the same as nothing being wrong',
      ),
    ];
  }

  final findings = <ConformanceFinding>[];
  for (final file in files) {
    final relative = file.path.substring(root.path.length + 1);
    // Comment-stripped, string-blanked: a TODO mentioning the bug or a
    // label string that happens to spell it out is not a call site.
    final lines = strippedDartSource(file.readAsStringSync()).split('\n');
    for (var i = 0; i < lines.length; i++) {
      for (final match in _bareCallPattern.allMatches(lines[i])) {
        final variant = match.group(1)!;
        findings.add(ConformanceFinding(
          _check,
          '$relative:${i + 1} calls IconButton.$variant( — use '
          'OhIconButton.$variant from openhearth_design, which pins the '
          "variant's own foreground",
        ));
      }
    }
  }
  return findings;
}

/// `\b` before `IconButton` is a word/non-word transition, so
/// `OhIconButton.filled(` — the fix, not the bug — never matches: `h` and
/// `I` are both word characters and there is no boundary between them. A
/// library-prefixed call (`material.IconButton.filled(`) still matches: the
/// `.` before `IconButton` is a non-word character, so the boundary is real.
final _bareCallPattern = RegExp(r'\bIconButton\.(filled|filledTonal)\(');

/// True when pubspec.yaml declares an `openhearth_design` dependency in any
/// form (path, hosted, override) — the same shape backup.dart's simple
/// dependency-key check uses. This is a presence gate, not a validation of
/// WHERE it points; C1 already owns "does it point at the canonical
/// package".
bool _dependsOnOpenhearthDesign(Directory root) {
  final pubspec = File('${root.path}/pubspec.yaml');
  if (!pubspec.existsSync()) return false;
  return _designDependencyPattern.hasMatch(pubspec.readAsStringSync());
}

final _designDependencyPattern =
    RegExp(r'^\s+openhearth_design\s*:', multiLine: true);
