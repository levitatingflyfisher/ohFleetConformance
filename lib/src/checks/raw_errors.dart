import 'dart:io';

import '../findings.dart';
import '../source_scan.dart';

const _check = 'C10-rawErrors';

/// C10 — no raw exception as user-visible text.
///
/// `Text('Error: $e')` puts a developer's string on a family's screen:
/// Lilt shipped "Error: Bad state: Name not found: does-not-exist-xyz" on an
/// empty scaffold with no way out (lilt finding 5, six screens), and the
/// same shape recurs across the fleet in error builders and snack bars.
/// ohStyle 0.7.0 ships the replacement: `OhErrorState` (a plain sentence,
/// one action, details behind a disclosure) and `ohFriendlyErrorMessage(e)`
/// for the one-line cases.
///
/// **Surfaces read** (all under `lib/`, comments never count): the first
/// positional argument of `Text(`/`SelectableText(` (which covers
/// `SnackBar(content: Text(...))` and dialog titles), `TextSpan(text:)`,
/// and any `errorText:` argument.
///
/// **What is raw.** In that expression, any of:
///  * `$x` / `${x}` / `${x.toString()}` interpolated, or `x.toString()`,
///    where `x` is `error`, `err`, `exception` or `exc` — or `e`/`ex` when
///    the same file binds it as an error (`catch (e`, `error: (e,`,
///    `onError: (e`, `(e, st)`-style callbacks). The binding requirement is
///    what keeps `labels.map((e) => Text('$e'))` quiet;
///  * `${something.error}` / `something.error.toString()` — an
///    `AsyncSnapshot`/`AsyncValue` error, raw by construction.
///
/// **False negatives, recorded honestly.** A raw error stored first and
/// shown later (`state = 'Failed: $e'` then `Text(state)`), passed to a
/// custom widget's `message:`, or carried in `e.message` is not seen; nor is
/// an error variable with any other name. **False positives:** a field
/// NAMED `error` that already holds a friendly sentence, interpolated into
/// a Text — rename it (`errorMessage`) or pass it bare (`Text(error)` is
/// never flagged: a bare String cannot be judged).
///
/// Cannot pass by finding nothing: no Dart sources, or sources with no
/// `Text(` anywhere, are findings.
List<ConformanceFinding> checkNoRawErrorText({required Directory root}) {
  final sources = ScannedSource.under(root);
  if (sources.isEmpty) {
    return const [
      ConformanceFinding(
        _check,
        'no Dart sources found under lib/ — nothing was swept, which is not '
        'the same as nothing being wrong',
      ),
    ];
  }

  final findings = <ConformanceFinding>[];
  var surfaces = 0;
  for (final src in sources) {
    final names = {..._alwaysErrorNames};
    for (final candidate in _bindableNames) {
      if (_bindsAsError(src.structure, candidate)) names.add(candidate);
    }
    final raw = _rawPatterns(names);

    void inspect(SourceRange expr, String surface) {
      final text = src.code.substring(expr.start, expr.end);
      if (raw.any((p) => p.hasMatch(text))) {
        findings.add(ConformanceFinding(
          _check,
          '${src.relative}:${lineOf(src.original, expr.start)} shows a raw '
          'exception as $surface (${text.trim().replaceAll(RegExp(r'\s+'), ' ')}) '
          '— use OhErrorState, or ohFriendlyErrorMessage(e) for one line '
          '(openhearth_design 0.7.0); log the exception, do not print it',
        ));
      }
    }

    for (final widget in const ['Text', 'SelectableText']) {
      for (final (open, close) in src.calls(widget)) {
        surfaces++;
        final args = topLevelArguments(src.structure, open, close);
        if (args.isEmpty) continue;
        final first = args.first;
        final firstText = src.structure.substring(first.start, first.end);
        if (RegExp(r'^\s*[A-Za-z_]\w*\s*:').hasMatch(firstText)) continue;
        inspect(first, '$widget text');
      }
    }
    for (final (open, close) in src.calls('TextSpan')) {
      surfaces++;
      final text = namedArgument(src.structure, open, close, 'text');
      if (text != null) inspect(text, 'TextSpan text');
    }
    for (final m in RegExp(r'\berrorText\s*:').allMatches(src.structure)) {
      final end = _expressionEnd(src.structure, m.end);
      inspect(SourceRange(m.end, end), 'errorText');
    }
  }

  if (surfaces == 0) {
    return const [
      ConformanceFinding(
        _check,
        'no Text/SelectableText/TextSpan found under lib/ — nothing was '
        'swept, which is not the same as nothing being wrong',
      ),
    ];
  }
  return findings;
}

const _alwaysErrorNames = {'error', 'err', 'exception', 'exc'};
const _bindableNames = {'e', 'ex'};

bool _bindsAsError(String structure, String name) {
  final n = RegExp.escape(name);
  return RegExp(
    '(catch\\s*\\(\\s*$n\\b)'
    '|(\\b(error|onError)\\s*:\\s*\\(\\s*$n\\b)'
    '|(\\(\\s*$n\\s*,\\s*(st|s|stack|stackTrace|trace|_)\\s*\\))',
  ).hasMatch(structure);
}

List<RegExp> _rawPatterns(Set<String> names) {
  final alt = names.map(RegExp.escape).join('|');
  return [
    // '$e' — the identifier must end there (not $errorCount).
    RegExp('\\\$($alt)(?![A-Za-z0-9_])'),
    // '${e}' / '${e.toString()}'
    RegExp('\\\$\\{\\s*($alt)\\s*(\\.toString\\(\\s*\\))?\\s*\\}'),
    // e.toString() as (part of) the expression
    RegExp('(?<![A-Za-z0-9_.])($alt)\\s*\\.toString\\(\\s*\\)'),
    // ${snapshot.error} / snapshot.error.toString()
    RegExp(r'\$\{\s*[A-Za-z_][\w.]*\.error\s*(\.toString\(\s*\))?\s*\}'),
    RegExp(r'[A-Za-z_][\w]*\.error\s*\.toString\(\s*\)'),
  ];
}

/// End offset of the expression starting at [start]: the first depth-zero
/// comma or closing bracket.
int _expressionEnd(String structure, int start) {
  var depth = 0;
  for (var i = start; i < structure.length; i++) {
    final c = structure[i];
    if (c == '(' || c == '[' || c == '{') {
      depth++;
    } else if (c == ')' || c == ']' || c == '}') {
      if (depth == 0) return i;
      depth--;
    } else if (c == ',' && depth == 0) {
      return i;
    }
  }
  return structure.length;
}
