/// Dart source with comments removed and string-literal contents blanked,
/// for the source-scanning checks: a `// BackupEnvelope.unwrap` comment or
/// a `'runStartupMaintenance()'` string must never satisfy a conformance
/// scan that is looking for real code.
///
/// Guarantees:
///  * line count is preserved (newlines inside comments and multi-line
///    strings are kept), so scanners can still report `file:line`;
///  * string QUOTES survive with empty contents (`'x'` → `''`), so the
///    surrounding code shape stays parseable-looking;
///  * nested block comments (Dart nests them) and raw strings are handled.
///
/// This is a cheap single-pass scanner, not a parser: interpolation bodies
/// (`'${...}'`) are blanked along with the string around them, which is
/// exactly what a conformance scan wants.
String strippedDartSource(String source) {
  final out = StringBuffer();
  var i = 0;
  final n = source.length;
  while (i < n) {
    final c = source[i];

    // Line comment — drop to end of line; the newline itself is emitted
    // by the main loop so line numbers survive.
    if (c == '/' && i + 1 < n && source[i + 1] == '/') {
      i += 2;
      while (i < n && source[i] != '\n') {
        i++;
      }
      continue;
    }

    // Block comment — Dart block comments nest, so track depth. Interior
    // newlines are re-emitted to preserve line numbers.
    if (c == '/' && i + 1 < n && source[i + 1] == '*') {
      var depth = 1;
      i += 2;
      while (i < n && depth > 0) {
        if (source[i] == '\n') {
          out.write('\n');
          i++;
        } else if (source[i] == '/' && i + 1 < n && source[i + 1] == '*') {
          depth++;
          i += 2;
        } else if (source[i] == '*' && i + 1 < n && source[i + 1] == '/') {
          depth--;
          i += 2;
        } else {
          i++;
        }
      }
      out.write(' ');
      continue;
    }

    // String literal — keep the quotes, blank the contents.
    if (c == "'" || c == '"') {
      final quote = c;
      final raw = i > 0 && (source[i - 1] == 'r' || source[i - 1] == 'R');
      final triple =
          i + 2 < n && source[i + 1] == quote && source[i + 2] == quote;
      out.write(quote);
      if (triple) {
        i += 3;
        while (i < n) {
          if (i + 2 < n &&
              source[i] == quote &&
              source[i + 1] == quote &&
              source[i + 2] == quote) {
            i += 3;
            break;
          }
          if (source[i] == '\n') {
            out.write('\n');
            i++;
          } else if (!raw && source[i] == r'\' && i + 1 < n) {
            if (source[i + 1] == '\n') out.write('\n');
            i += 2;
          } else {
            i++;
          }
        }
      } else {
        i += 1;
        while (i < n && source[i] != quote && source[i] != '\n') {
          if (!raw && source[i] == r'\' && i + 1 < n) {
            i += 2;
          } else {
            i++;
          }
        }
        if (i < n && source[i] == quote) i++;
        // An unterminated line leaves its newline for the main loop.
      }
      out.write(quote);
      continue;
    }

    out.write(c);
    i++;
  }
  return out.toString();
}
