import 'dart:io';

/// Offset-preserving scanning helpers for the checks that need to read the
/// SHAPE of a call (C9–C12): which arguments a `GoRoute(` or an
/// `IconButton(` was given, and where.
///
/// [strippedDartSource] (dart_source.dart) is the right tool for "does this
/// token appear in real code"; it cannot answer "which argument of which
/// call", because it drops comments and string bodies and so shifts every
/// offset after them. [maskedDartSource] blanks the same things to spaces
/// instead, so one offset means the same place in the original, in the
/// strings-kept mask, and in the strings-blanked mask.

/// [source] with every comment character replaced by a space and — when
/// [maskStrings] — every string-literal body character replaced by a space
/// (quotes kept). Newlines are never replaced, so length, offsets and line
/// numbers are identical to [source].
///
/// Lexing rules match [strippedDartSource]: nested block comments, raw
/// strings, triple quotes, backslash escapes. Interpolation bodies are part
/// of the string and are masked with it.
String maskedDartSource(String source, {bool maskStrings = true}) =>
    _scan(source, maskStrings, null);

/// The body span of every string literal in [source], in order (quotes
/// excluded; an interpolation is part of the body it sits in).
List<SourceRange> stringLiteralBodies(String source) {
  final bodies = <SourceRange>[];
  _scan(source, true, bodies);
  return bodies;
}

String _scan(String source, bool maskStrings, List<SourceRange>? bodies) {
  final out = StringBuffer();
  var i = 0;
  final n = source.length;
  void blank(int from, int to) {
    for (var k = from; k < to; k++) {
      out.write(source[k] == '\n' ? '\n' : ' ');
    }
  }

  while (i < n) {
    final c = source[i];
    if (c == '/' && i + 1 < n && source[i + 1] == '/') {
      final start = i;
      while (i < n && source[i] != '\n') {
        i++;
      }
      blank(start, i);
      continue;
    }
    if (c == '/' && i + 1 < n && source[i + 1] == '*') {
      final start = i;
      var depth = 1;
      i += 2;
      while (i < n && depth > 0) {
        if (source[i] == '/' && i + 1 < n && source[i + 1] == '*') {
          depth++;
          i += 2;
        } else if (source[i] == '*' && i + 1 < n && source[i + 1] == '/') {
          depth--;
          i += 2;
        } else {
          i++;
        }
      }
      blank(start, i);
      continue;
    }
    if (c == "'" || c == '"') {
      final quote = c;
      final raw = i > 0 && (source[i - 1] == 'r' || source[i - 1] == 'R');
      final triple =
          i + 2 < n && source[i + 1] == quote && source[i + 2] == quote;
      final open = triple ? 3 : 1;
      out.write(source.substring(i, i + open));
      i += open;
      final bodyStart = i;
      var closeLen = 0;
      while (i < n) {
        if (triple) {
          if (i + 2 < n &&
              source[i] == quote &&
              source[i + 1] == quote &&
              source[i + 2] == quote) {
            closeLen = 3;
            break;
          }
        } else if (source[i] == quote) {
          closeLen = 1;
          break;
        } else if (source[i] == '\n') {
          break; // unterminated single-line string
        }
        if (!raw && source[i] == r'\' && i + 1 < n) {
          i += 2;
        } else {
          i++;
        }
      }
      if (i > n) i = n;
      bodies?.add(SourceRange(bodyStart, i));
      if (maskStrings) {
        blank(bodyStart, i);
      } else {
        out.write(source.substring(bodyStart, i));
      }
      out.write(source.substring(i, i + closeLen));
      i += closeLen;
      continue;
    }
    out.write(c);
    i++;
  }
  return out.toString();
}

/// A half-open `[start, end)` span of source offsets.
class SourceRange {
  final int start;
  final int end;
  const SourceRange(this.start, this.end);
}

const _opens = {'(': ')', '[': ']', '{': '}'};

/// Index of the bracket closing the one at [openIndex] in [masked] (which
/// must have strings and comments masked), or null when unbalanced.
int? matchingClose(String masked, int openIndex) {
  var depth = 0;
  for (var i = openIndex; i < masked.length; i++) {
    final c = masked[i];
    if (_opens.containsKey(c)) {
      depth++;
    } else if (c == ')' || c == ']' || c == '}') {
      depth--;
      if (depth == 0) return i;
    }
  }
  return null;
}

/// The comma-separated arguments strictly between [open] and [close]
/// (bracket indices), split only at bracket depth zero.
List<SourceRange> topLevelArguments(String masked, int open, int close) {
  final args = <SourceRange>[];
  var depth = 0;
  var start = open + 1;
  for (var i = open + 1; i < close; i++) {
    final c = masked[i];
    if (_opens.containsKey(c)) {
      depth++;
    } else if (c == ')' || c == ']' || c == '}') {
      depth--;
    } else if (c == ',' && depth == 0) {
      args.add(SourceRange(start, i));
      start = i + 1;
    }
  }
  if (masked.substring(start, close).trim().isNotEmpty) {
    args.add(SourceRange(start, close));
  }
  return args;
}

/// The value span of the depth-zero named argument `label:` between the
/// brackets at [open] and [close], or null when the call has no such
/// argument.
SourceRange? namedArgument(String masked, int open, int close, String label) {
  final pattern = RegExp('^\\s*${RegExp.escape(label)}\\s*:');
  for (final arg in topLevelArguments(masked, open, close)) {
    final m = pattern.firstMatch(masked.substring(arg.start, arg.end));
    if (m != null) return SourceRange(arg.start + m.end, arg.end);
  }
  return null;
}

final _singleLiteral = RegExp(r'''^\s*r?(?:'([^'\n]*)'|"([^"\n]*)")\s*$''');

/// The contents of [expression] when it is exactly one single-line string
/// literal (read from a strings-KEPT mask), else null — `'/a' + x` and
/// `Routes.a` are expressions this scanner will not evaluate.
String? singleStringLiteral(String expression) {
  final m = _singleLiteral.firstMatch(expression);
  if (m == null) return null;
  return m.group(1) ?? m.group(2);
}

/// 1-based line number of [offset] in [source].
int lineOf(String source, int offset) =>
    '\n'.allMatches(source.substring(0, offset)).length + 1;

/// Authored Dart sources under `<root>/<dir>`, sorted (directory order is
/// platform-dependent; findings must not be). Generated `.g.dart` and
/// `.freezed.dart` files are build products, not authored code.
List<File> authoredDartFiles(Directory root, [String dir = 'lib']) {
  final d = Directory('${root.path}/$dir');
  if (!d.existsSync()) return <File>[];
  return d
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) =>
          f.path.endsWith('.dart') &&
          !f.path.endsWith('.g.dart') &&
          !f.path.endsWith('.freezed.dart'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
}

/// Path of [file] relative to [root], for findings.
String relativePath(Directory root, File file) =>
    file.path.substring(root.path.length + 1);

/// One authored file, read once and masked both ways at identical offsets.
class ScannedSource {
  final String relative;
  final String original;

  /// Comments masked, strings kept — read literal contents here.
  final String code;

  /// Comments AND string bodies masked — match structure here.
  final String structure;

  /// Body spans of every string literal, at the same offsets.
  final List<SourceRange> literals;

  ScannedSource(this.relative, this.original)
      : code = maskedDartSource(original, maskStrings: false),
        structure = maskedDartSource(original),
        literals = stringLiteralBodies(original);

  /// The text of one literal body.
  String literalText(SourceRange body) =>
      original.substring(body.start, body.end);

  static List<ScannedSource> under(Directory root, [String dir = 'lib']) =>
      authoredDartFiles(root, dir)
          .map((f) => ScannedSource(relativePath(root, f), f.readAsStringSync()))
          .toList();

  /// Every call `name(` (word-bounded, so `OhIconButton(` is not
  /// `IconButton(`) with its open/close paren indices. Unbalanced calls are
  /// skipped.
  Iterable<(int open, int close)> calls(String name) sync* {
    final pattern = RegExp('(?<![A-Za-z0-9_])${RegExp.escape(name)}\\s*\\(');
    for (final m in pattern.allMatches(structure)) {
      final open = m.end - 1;
      final close = matchingClose(structure, open);
      if (close != null) yield (open, close);
    }
  }
}
