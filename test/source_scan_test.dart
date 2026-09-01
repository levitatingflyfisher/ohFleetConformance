import 'package:flutter_test/flutter_test.dart';
import 'package:oh_fleet_conformance/src/source_scan.dart';

void main() {
  group('maskedDartSource', () {
    test('preserves length and every newline offset', () {
      const source = "final a = 'x(y'; // comment (\n"
          '/* block\n ( */ final b = "q";\n'
          "final c = '''multi\nline''';\n";
      for (final maskStrings in [true, false]) {
        final masked = maskedDartSource(source, maskStrings: maskStrings);
        expect(masked.length, source.length);
        for (var i = 0; i < source.length; i++) {
          if (source[i] == '\n') expect(masked[i], '\n');
        }
      }
    });

    test('blanks comments to spaces, never to nothing', () {
      final masked = maskedDartSource('a; // context.go(x)\nb;');
      expect(masked, isNot(contains('context')));
      expect(masked.indexOf('b;'), 'a; // context.go(x)\n'.length);
    });

    test('blanks nested block comments', () {
      final masked = maskedDartSource('/* a /* b */ c */ d');
      expect(masked.trim(), 'd');
    });

    test('maskStrings blanks bodies but keeps quotes', () {
      final masked = maskedDartSource("f('a(b');");
      expect(masked, "f('   ');");
    });

    test('maskStrings: false keeps string bodies, still blanks comments', () {
      final masked =
          maskedDartSource("f('/x'); // '/y'\n", maskStrings: false);
      expect(masked, contains("'/x'"));
      expect(masked, isNot(contains('/y')));
    });

    test('an escaped quote does not end a string', () {
      final masked = maskedDartSource(r"f('it\'s (');g();");
      expect(masked, "f('       ');g();");
    });

    test('raw strings treat backslash literally', () {
      final masked = maskedDartSource(r"f(r'a\');g();");
      expect(masked, endsWith('g();'));
    });
  });

  test('stringLiteralBodies finds every body, not comment quotes', () {
    const source = "a('/x', \"it's\"); // '/no'\nb('''/y''');";
    final bodies = stringLiteralBodies(source)
        .map((r) => source.substring(r.start, r.end))
        .toList();
    expect(bodies, ['/x', "it's", '/y']);
  });

  group('span helpers', () {
    test('matchingClose balances parens, brackets and braces', () {
      const s = 'f(a, [b, (c)], {d: e})';
      expect(matchingClose(s, 1), s.length - 1);
      expect(matchingClose(s, s.indexOf('[')), s.indexOf(']'));
    });

    test('matchingClose returns null when unbalanced', () {
      expect(matchingClose('f(a, (b)', 1), isNull);
    });

    test('topLevelArguments splits only at depth zero', () {
      const s = 'f(a, g(b, c), [d, e], x: y)';
      final args = topLevelArguments(s, 1, s.length - 1)
          .map((r) => s.substring(r.start, r.end).trim())
          .toList();
      expect(args, ['a', 'g(b, c)', '[d, e]', 'x: y']);
    });

    test('namedArgument finds a depth-zero label only', () {
      const s = 'GoRoute(builder: (c, s) => X(path: z), path: p)';
      final r = namedArgument(s, 7, s.length - 1, 'path')!;
      expect(s.substring(r.start, r.end).trim(), 'p');
    });

    test('namedArgument is null when absent', () {
      const s = 'IconButton(icon: i, onPressed: f)';
      expect(namedArgument(s, 10, s.length - 1, 'tooltip'), isNull);
    });

    test('singleStringLiteral reads one literal, rejects expressions', () {
      expect(singleStringLiteral(" '/a/b' "), '/a/b');
      expect(singleStringLiteral('"/a"'), '/a');
      expect(singleStringLiteral("'/a' + x"), isNull);
      expect(singleStringLiteral('Routes.a'), isNull);
    });

    test('lineOf is 1-based', () {
      expect(lineOf('a\nb\nc', 0), 1);
      expect(lineOf('a\nb\nc', 4), 3);
    });
  });
}
