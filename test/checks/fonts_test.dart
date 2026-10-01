import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:oh_fleet_conformance/oh_fleet_conformance.dart';

/// Builds a structurally valid TrueType file whose cmap covers exactly
/// [ranges].
///
/// Synthesizing the font beats shipping a 47 KB binary fixture: the ranges
/// are stated in the test, so an assertion about coverage is checkable by
/// reading it. The real fonts are exercised where it counts — in the apps,
/// against their own `lib/`.
Uint8List fontCovering(List<(int, int)> ranges) {
  // Format 4 requires the terminator segment ending at 0xFFFF.
  final segs = [...ranges, (0xFFFF, 0xFFFF)];
  final segCount = segs.length;

  final sub = BytesBuilder();
  void u16(BytesBuilder b, int v) => b.add([(v >> 8) & 0xFF, v & 0xFF]);

  u16(sub, 4); // format
  u16(sub, 16 + segCount * 8); // length
  u16(sub, 0); // language
  u16(sub, segCount * 2); // segCountX2
  u16(sub, 0); // searchRange
  u16(sub, 0); // entrySelector
  u16(sub, 0); // rangeShift
  for (final s in segs) {
    u16(sub, s.$2); // endCode
  }
  u16(sub, 0); // reservedPad
  for (final s in segs) {
    u16(sub, s.$1); // startCode
  }
  for (final _ in segs) {
    u16(sub, 0); // idDelta
  }
  for (final _ in segs) {
    u16(sub, 0); // idRangeOffset
  }
  final subtable = sub.toBytes();

  final cmap = BytesBuilder();
  u16(cmap, 0); // version
  u16(cmap, 1); // numTables
  u16(cmap, 3); // platformID (Windows)
  u16(cmap, 1); // encodingID (BMP)
  cmap.add([0, 0, 0, 12]); // offset to subtable, from cmap start
  cmap.add(subtable);
  final cmapTable = cmap.toBytes();

  const numTables = 1;
  final cmapOffset = 12 + 16 * numTables;

  final out = BytesBuilder();
  out.add([0x00, 0x01, 0x00, 0x00]); // sfntVersion
  u16(out, numTables);
  u16(out, 0); // searchRange
  u16(out, 0); // entrySelector
  u16(out, 0); // rangeShift
  out.add('cmap'.codeUnits);
  out.add([0, 0, 0, 0]); // checksum
  out.add([
    (cmapOffset >> 24) & 0xFF,
    (cmapOffset >> 16) & 0xFF,
    (cmapOffset >> 8) & 0xFF,
    cmapOffset & 0xFF,
  ]);
  final len = cmapTable.length;
  out.add([
    (len >> 24) & 0xFF,
    (len >> 16) & 0xFF,
    (len >> 8) & 0xFF,
    len & 0xFF,
  ]);
  out.add(cmapTable);
  return out.toBytes();
}

void main() {
  late Directory parent;
  late Directory root;

  // The app sits beside a sibling design package, as the fleet's apps sit
  // beside ohStyle, so relative `rootUri`s and `path:` deps are realistic.
  setUp(() {
    parent = Directory.systemTemp.createTempSync('oh_fonts_');
    root = Directory('${parent.path}/app')..createSync();
  });
  tearDown(() => parent.deleteSync(recursive: true));

  /// Writes a minimal app: one `fonts:` block, the font files it names, and
  /// whatever Dart sources the test cares about.
  void app({
    required Map<String, List<(int, int)>> families,
    Map<String, String> lib = const {'main.dart': 'const a = 1;'},
    String? rawFontsBlock,
    bool dependsOnDesign = false,
  }) {
    final buf = StringBuffer('name: fixture\n\n');
    if (dependsOnDesign) {
      buf.write('dependencies:\n'
          '  openhearth_design:\n'
          '    path: ../ohStyle/openhearth_design\n\n');
    }
    buf.write('flutter:\n  uses-material-design: true\n');
    if (rawFontsBlock != null) {
      buf.write(rawFontsBlock);
    } else if (families.isNotEmpty) {
      buf.write('  fonts:\n');
      for (final f in families.entries) {
        buf.write('    - family: ${f.key}\n      fonts:\n');
        buf.write('        - asset: assets/fonts/${f.key}-Regular.ttf\n');
        buf.write('        - asset: assets/fonts/${f.key}-Bold.ttf\n'
            '          weight: 700\n');
      }
    }
    File('${root.path}/pubspec.yaml').writeAsStringSync(buf.toString());

    final fontDir = Directory('${root.path}/assets/fonts')
      ..createSync(recursive: true);
    for (final f in families.entries) {
      File('${fontDir.path}/${f.key}-Regular.ttf')
          .writeAsBytesSync(fontCovering(f.value));
      // Bold deliberately covers everything: the check must read the
      // regular weight, which is the one body text renders from.
      File('${fontDir.path}/${f.key}-Bold.ttf')
          .writeAsBytesSync(fontCovering([(0x20, 0xFFFE)]));
    }

    final libDir = Directory('${root.path}/lib')..createSync(recursive: true);
    for (final e in lib.entries) {
      final f = File('${libDir.path}/${e.key}');
      f.parent.createSync(recursive: true);
      f.writeAsStringSync(e.value);
    }
  }

  /// What a real body font covers: ASCII, Latin-1 (so the middle dot every
  /// app's date labels use), Latin Extended-A, and the general punctuation
  /// run that holds dashes and curly quotes.
  const latin = [(0x20, 0x7E), (0xA0, 0xFF), (0x100, 0x17F), (0x2010, 0x201D)];

  /// Writes the sibling `openhearth_design` package: a pubspec declaring
  /// [families] as package fonts (regular + bold each) and the files it names.
  /// With [packageConfig], also writes the app's `.dart_tool/package_config.json`
  /// pointing at it the way `pub get` does — relative to `.dart_tool/`.
  void design({
    required Map<String, List<(int, int)>> families,
    bool packageConfig = true,
  }) {
    final pkg = Directory('${parent.path}/ohStyle/openhearth_design')
      ..createSync(recursive: true);
    final buf = StringBuffer('name: openhearth_design\n\nflutter:\n');
    if (families.isNotEmpty) {
      buf.write('  fonts:\n');
      for (final f in families.entries) {
        buf.write('    - family: ${f.key}\n      fonts:\n');
        buf.write('        - asset: fonts/${f.key}-Regular.ttf\n');
        buf.write('        - asset: fonts/${f.key}-Bold.ttf\n'
            '          weight: 700\n');
      }
    }
    File('${pkg.path}/pubspec.yaml').writeAsStringSync(buf.toString());
    final fontDir = Directory('${pkg.path}/fonts')..createSync();
    for (final f in families.entries) {
      File('${fontDir.path}/${f.key}-Regular.ttf')
          .writeAsBytesSync(fontCovering(f.value));
      File('${fontDir.path}/${f.key}-Bold.ttf')
          .writeAsBytesSync(fontCovering([(0x20, 0xFFFE)]));
    }
    if (packageConfig) {
      final dt = Directory('${root.path}/.dart_tool')..createSync();
      File('${dt.path}/package_config.json').writeAsStringSync('''
{
  "configVersion": 2,
  "packages": [
    {
      "name": "openhearth_design",
      "rootUri": "../../ohStyle/openhearth_design",
      "packageUri": "lib/",
      "languageVersion": "3.3"
    }
  ]
}
''');
    }
  }

  group('package fonts (openhearth_design)', () {
    test('an app with no local fonts is checked against the package fonts',
        () {
      app(families: const {}, dependsOnDesign: true, lib: {
        'main.dart': "const greeting = 'Hello — café · 3';",
      });
      design(families: {'Lora': latin, 'Nunito': latin});
      expect(checkFontCoverage(root: root), isEmpty);
    });

    test('a literal the package fonts cannot draw is flagged', () {
      // Proves the characters are really checked against the package cmaps,
      // not merely that the "no fonts" finding went away.
      app(families: const {}, dependsOnDesign: true, lib: {
        'targets.dart': "const mark = '≤ 2200 kcal';",
      });
      design(families: {'Lora': latin, 'Nunito': latin});
      final findings = checkFontCoverage(root: root);
      expect(findings, hasLength(1));
      expect(findings.single.message, contains('U+2264'));
    });

    test('bundledFontCoverage includes the package families', () {
      app(families: const {}, dependsOnDesign: true);
      design(families: {'Lora': latin});
      final covered = bundledFontCoverage(root: root);
      expect(covered, contains(0x00B7));
      expect(covered, isNot(contains(0x2264)));
    });

    test('package and app families intersect', () {
      app(families: {'Local': latin}, dependsOnDesign: true);
      design(families: {
        'Lora': const [(0x20, 0x7E), (0xA0, 0xFF), (0x100, 0x17F)],
      });
      expect(bundledFontCoverage(root: root), isNot(contains(0x2019)),
          reason: 'text in an OhTypography style lands in the package Lora');
    });

    test('falls back to the pubspec path dep when .dart_tool is absent', () {
      app(families: const {}, dependsOnDesign: true, lib: {
        'targets.dart': "const mark = '≥';",
      });
      design(families: {'Lora': latin}, packageConfig: false);
      final findings = checkFontCoverage(root: root);
      expect(findings, hasLength(1));
      expect(findings.single.message, contains('U+2265'));
    });

    test('no app fonts and no package fonts is still a finding', () {
      app(families: const {}, dependsOnDesign: true);
      design(families: const {});
      final findings = checkFontCoverage(root: root);
      expect(findings, isNotEmpty);
      expect(findings.first.message, contains('no bundled font'));
    });

    test('a missing package font file is a finding naming the package', () {
      app(families: const {}, dependsOnDesign: true);
      design(families: {'Lora': latin, 'Nunito': latin});
      File('${parent.path}/ohStyle/openhearth_design/fonts/Lora-Regular.ttf')
          .deleteSync();
      final findings = checkFontCoverage(root: root);
      expect(findings.map((f) => f.message).join(),
          allOf(contains('openhearth_design'), contains('Lora-Regular.ttf')));
    });
  });

  group('bundledFontCoverage', () {
    test('reads exactly the ranges the cmap declares', () {
      app(families: {'Fix': latin});
      final covered = bundledFontCoverage(root: root);
      expect(covered, contains(0x41)); // A
      expect(covered, contains(0x00B7)); // ·
      expect(covered, isNot(contains(0x2264))); // ≤
      expect(covered, isNot(contains(0xFFFF))); // terminator is not coverage
    });

    test('intersects families — a glyph only one font has is not safe', () {
      app(families: {
        'Alpha': latin,
        // Same body coverage, no general punctuation.
        'Beta': const [(0x20, 0x7E), (0xA0, 0xFF), (0x100, 0x17F)],
      });
      final covered = bundledFontCoverage(root: root);
      expect(covered, contains(0x41));
      expect(covered, isNot(contains(0x2019)),
          reason: 'Beta cannot draw it, so text landing in Beta boxes');
    });
  });

  group('checkFontCoverage', () {
    test('is silent for an app whose literals all draw', () {
      app(families: {'Fix': latin}, lib: {
        'main.dart': "const greeting = 'Hello — café';",
      });
      expect(checkFontCoverage(root: root), isEmpty);
    });

    test('flags a literal the bundled fonts cannot draw', () {
      app(families: {'Fix': latin}, lib: {
        'targets.dart': "const mark = '≤ 2200 kcal';",
      });
      final findings = checkFontCoverage(root: root);
      expect(findings, hasLength(1));
      expect(findings.single.message, contains('U+2264'));
      expect(findings.single.message, contains('targets.dart'));
    });

    test('exempts emoji — the OS draws those from its own colour font', () {
      app(families: {'Fix': latin}, lib: {
        'main.dart': "const icon = '🍎';\nconst family = '👩‍👦';",
      });
      expect(checkFontCoverage(root: root), isEmpty);
    });

    test('exempts regex character classes and marked lines', () {
      app(families: {'Fix': latin}, lib: {
        'parse.dart': "final money = RegExp(r'[\\s\$€£¥₹]');\n"
            "const sep = '→'; // not-rendered\n"
            "// a comment mentioning ≥ is prose, never drawn\n",
      });
      expect(checkFontCoverage(root: root), isEmpty);
    });

    test('ignores generated sources', () {
      // A hand-written file has to be present too, or the empty-lib guard
      // fires and the exclusion proves nothing.
      app(families: {'Fix': latin}, lib: {
        'main.dart': "const ok = 'café';",
        'model.g.dart': "const x = '≥';",
      });
      expect(checkFontCoverage(root: root), isEmpty);
    });

    test('reports every offender, not just the first', () {
      app(families: {'Fix': latin}, lib: {
        'a.dart': "const x = '≤';",
        'b.dart': "const y = '→';",
      });
      expect(checkFontCoverage(root: root), hasLength(2));
    });
  });

  group('escapes are decoded before the sweep', () {
    // Every fixture below writes a literal backslash in the Dart source, so
    // the old raw-rune sweep saw only ASCII and passed it.
    test('a \\uXXXX escape the fonts cannot draw is a finding', () {
      app(families: {'Fix': latin}, lib: {
        'onboarding.dart': r"const next = 'Skip \u2192';",
      });
      final findings = checkFontCoverage(root: root);
      expect(findings, hasLength(1));
      expect(findings.single.message, contains('U+2192'));
      expect(findings.single.message, contains('onboarding.dart'));
    });

    test('a \\u{...} escape is decoded too', () {
      app(families: {'Fix': latin}, lib: {
        'results.dart': r'const tau = "Kendall \u{3C4}";',
      });
      final findings = checkFontCoverage(root: root);
      expect(findings, hasLength(1));
      expect(findings.single.message, contains('U+03C4'));
    });

    test('a \\xHH escape is decoded too', () {
      app(families: {'Fix': latin}, lib: {
        'a.dart': r"const x = 'a\xB7b';", // drawable: middle dot
        'b.dart': r"const y = 'a\x80b';", // a C1 control: not drawable
      });
      final findings = checkFontCoverage(root: root);
      expect(findings, hasLength(1));
      expect(findings.single.message, contains('U+0080'));
    });

    test('a drawable escape is silent', () {
      app(families: {'Fix': latin}, lib: {
        'main.dart': r"const s = 'That\u2019s me \u2014 caf\u00e9';",
      });
      expect(checkFontCoverage(root: root), isEmpty);
    });

    test('a raw string is not decoded — r"\\u2192" prints a backslash', () {
      app(families: {'Fix': latin}, lib: {
        'main.dart': r"const s = r'\u2192';" "\n" r'const t = r"\u{3C4}";',
      });
      expect(checkFontCoverage(root: root), isEmpty);
    });

    test('an escaped backslash does not start an escape', () {
      app(families: {'Fix': latin}, lib: {
        'main.dart': r"const s = 'C:\\u2192';",
      });
      expect(checkFontCoverage(root: root), isEmpty);
    });
  });

  group('apps that ship a web build', () {
    void web() {
      Directory('${root.path}/web').createSync();
      File('${root.path}/web/index.html').writeAsStringSync('<html></html>');
    }

    test('emoji are findings: the web has no platform colour font', () {
      app(families: {'Fix': latin}, lib: {
        'profile.dart': "const avatar = '👤';",
      });
      web();
      final findings = checkFontCoverage(root: root);
      expect(findings, hasLength(1));
      expect(findings.single.message, contains('U+1F464'));
      expect(findings.single.message, contains('web'));
    });

    test('an escaped emoji surrogate pair decodes to one emoji', () {
      app(families: {'Fix': latin}, lib: {
        'profile.dart': r"const avatar = '\uD83D\uDC64';",
      });
      web();
      final findings = checkFontCoverage(root: root);
      expect(findings, hasLength(1));
      expect(findings.single.message, contains('U+1F464'));
    });

    test('ZWJ and variation selectors are findings too', () {
      app(families: {'Fix': latin}, lib: {
        'a.dart': "const heart = 'x\u{FE0F}';",
        'b.dart': "const glue = 'x\u200Dy';",
      });
      web();
      expect(checkFontCoverage(root: root), hasLength(2));
    });

    test('without web/index.html emoji keep their native exemption', () {
      app(families: {'Fix': latin}, lib: {
        'profile.dart': r"const avatar = '\u{1F464}';",
      });
      Directory('${root.path}/web').createSync(); // no index.html: no build
      expect(checkFontCoverage(root: root), isEmpty);
    });

    test('undrawableIn is strict when asked for the web', () {
      final drawable = {for (var c = 0x20; c < 0x7F; c++) c};
      expect(undrawableIn('🍎 pie', drawable), isEmpty);
      expect(undrawableIn('🍎 pie', drawable, web: true), hasLength(1));
    });
  });

  group('the check cannot pass vacuously', () {
    test('an app that declares no fonts is a finding, not a free pass', () {
      app(families: const {});
      final findings = checkFontCoverage(root: root);
      expect(findings, isNotEmpty);
      expect(findings.first.message, contains('no bundled font'));
    });

    test('a font whose cmap yields implausibly few glyphs is a finding', () {
      // The failure mode that matters: a parse that quietly returns nothing
      // makes every literal "drawable" and the whole check theatre.
      app(families: {'Fix': const [(0x41, 0x43)]});
      final findings = checkFontCoverage(root: root);
      expect(findings, isNotEmpty);
      expect(findings.first.message, contains('only 3'));
    });

    test('a font missing the middle dot is a finding', () {
      // Plenty of coverage overall — the gap is one character wide, which is
      // exactly how the real bug hid.
      app(families: {
        'Fix': const [(0x20, 0x7E), (0xB8, 0xFF), (0x100, 0x17F), (0x2018, 0x201D)],
      });
      final findings = checkFontCoverage(root: root);
      expect(findings, isNotEmpty);
      expect(findings.map((f) => f.message).join(), contains('U+00B7'));
    });

    test('an empty lib/ is a finding — nothing swept is not nothing wrong',
        () {
      app(families: {'Fix': latin}, lib: const {});
      final findings = checkFontCoverage(root: root);
      expect(findings, isNotEmpty);
      expect(findings.first.message, contains('no Dart sources'));
    });

    test('a declared font file that is missing is a finding', () {
      app(families: {'Fix': latin});
      File('${root.path}/assets/fonts/Fix-Regular.ttf').deleteSync();
      final findings = checkFontCoverage(root: root);
      expect(findings, isNotEmpty);
      expect(findings.first.message, contains('Fix-Regular.ttf'));
    });
  });
}
