import 'dart:io';

import '../dart_source.dart';
import '../findings.dart';

const _check = 'C14-snackBarPersist';

/// C14 — every `SnackBar(` that has an `action:` states `persist:`.
///
/// On the fleet's Flutter, `SnackBar` defaults `persist` to
/// `action != null`: a snack bar with an action stays up until it is
/// tapped, ignoring its duration, and follows the person across screens.
/// Lullaby's "Wet diaper logged / EDIT" sat on screen for minutes; Sundial's
/// "Session saved / Add notes", Peckish's "Logged / Undo" and three Trellis
/// lines did the same. Nothing about the call site says so, which is why
/// it took an emulator run to see. The check asks each such call site to
/// decide out loud: `persist: false` for a convenience action that may
/// lapse, `persist: true` only where staying is the point (a fleet Undo
/// for a deliberate delete uses `OhUndoBar`, not a snack bar).
///
/// `lib/` only, comments and string contents blanked. No Dart sources is a
/// finding: nothing swept is not nothing wrong.
List<ConformanceFinding> checkSnackBarPersist({required Directory root}) {
  final lib = Directory('${root.path}/lib');
  final files = lib.existsSync()
      ? (lib
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) =>
              f.path.endsWith('.dart') &&
              !f.path.endsWith('.g.dart') &&
              !f.path.endsWith('.freezed.dart'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path)))
      : <File>[];
  if (files.isEmpty) {
    return const [
      ConformanceFinding(_check,
          'no Dart sources found under lib/ — nothing was swept, which is '
          'not the same as nothing being wrong'),
    ];
  }

  final findings = <ConformanceFinding>[];
  for (final file in files) {
    final relative = file.path.substring(root.path.length + 1);
    final src = strippedDartSource(file.readAsStringSync());
    for (final m in _call.allMatches(src)) {
      final args = _argsFrom(src, m.end);
      if (!_named('action').hasMatch(args)) continue;
      if (_named('persist').hasMatch(args)) continue;
      final line = '\n'.allMatches(src.substring(0, m.start)).length + 1;
      findings.add(ConformanceFinding(
        _check,
        '$relative:$line builds a SnackBar with an action but no persist: — '
        'Flutter then keeps it up until tapped, across screens. Say '
        'persist: false (a convenience that may lapse) or persist: true',
      ));
    }
  }
  return findings;
}

/// A `SnackBar(` call, not `SnackBarAction(` or `showSnackBar(`.
final _call = RegExp(r'(?<![\w.])SnackBar\(');

/// `name:` as a named argument at the call's own depth is good enough here:
/// a nested `SnackBarAction(...)` never has `action:` or `persist:`.
RegExp _named(String name) => RegExp('(?<![\\w.])$name\\s*:');

/// The argument text of the call whose `(` ends at [open] (balanced).
String _argsFrom(String src, int open) {
  var depth = 1;
  var i = open;
  while (i < src.length && depth > 0) {
    final c = src[i];
    if (c == '(' || c == '[' || c == '{') depth++;
    if (c == ')' || c == ']' || c == '}') depth--;
    i++;
  }
  return src.substring(open, i - 1);
}
