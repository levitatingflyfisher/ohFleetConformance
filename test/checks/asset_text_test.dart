import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oh_fleet_conformance/oh_fleet_conformance.dart';

import 'fonts_test.dart' show fontCovering;

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('oh_asset_text_'));
  tearDown(() => root.deleteSync(recursive: true));

  /// ASCII, Latin-1, Latin Extended-A and general punctuation: a real body
  /// font's coverage, so a middle dot and curly quotes draw and an arrow
  /// (U+2192) or ≤ does not.
  const latin = [(0x20, 0x7E), (0xA0, 0xFF), (0x100, 0x17F), (0x2010, 0x201D)];

  /// A minimal app: one bundled family, the given `assets:` entries, and the
  /// files on disk (path → text, or bytes for a binary asset).
  void app({
    required List<String> assets,
    Map<String, Object> files = const {},
    bool web = false,
  }) {
    final buf = StringBuffer('name: fixture\n\nflutter:\n'
        '  uses-material-design: true\n');
    if (assets.isNotEmpty) {
      buf.write('  assets:\n');
      for (final a in assets) {
        buf.write('    $a\n');
      }
    }
    buf.write('  fonts:\n'
        '    - family: Fix\n'
        '      fonts:\n'
        '        - asset: fonts/Fix-Regular.ttf\n');
    File('${root.path}/pubspec.yaml').writeAsStringSync(buf.toString());
    Directory('${root.path}/fonts').createSync();
    File('${root.path}/fonts/Fix-Regular.ttf')
        .writeAsBytesSync(fontCovering(latin));
    for (final e in files.entries) {
      final f = File('${root.path}/${e.key}')..parent.createSync(recursive: true);
      final v = e.value;
      if (v is String) {
        f.writeAsStringSync(v);
      } else {
        f.writeAsBytesSync(v as List<int>);
      }
    }
    if (web) {
      Directory('${root.path}/web').createSync();
      File('${root.path}/web/index.html').writeAsStringSync('<html></html>');
    }
  }

  List<String> messages(
          {Map<String, String> exemptions = const {},
          Map<String, String> fallback = const {}}) =>
      [
        for (final f in checkAssetTextCoverage(
            root: root, exemptions: exemptions, latinFallback: fallback))
          f.message,
      ];

  group('JSON assets', () {
    test('a string value the fonts cannot draw is a finding', () {
      app(assets: ['- assets/data/canon.json'], files: {
        'assets/data/canon.json': '{"title": "Wabi → Sabi"}',
      });
      final m = messages();
      expect(m, hasLength(1));
      expect(m.single, allOf(contains('U+2192'), contains('canon.json')));
    });

    test('a JSON escape is decoded before the check', () {
      app(assets: ['- assets/data/canon.json'], files: {
        'assets/data/canon.json': r'{"title": "Ma 間"}',
      });
      expect(messages().single, contains('U+9593'));
    });

    test('keys are identifiers, never drawn, so they are not checked', () {
      app(assets: ['- assets/data/canon.json'], files: {
        'assets/data/canon.json': '{"→": "plain café · ok"}',
      });
      expect(messages(), isEmpty);
    });

    test('content is sniffed: JSON under any extension is read as JSON', () {
      app(assets: ['- assets/courses/kalman.ohcourse'], files: {
        'assets/courses/kalman.ohcourse': '{"step": "x ≤ y"}',
      });
      expect(messages().single, contains('U+2264'));
    });
  });

  group('other text assets', () {
    test('a plain text file is checked rune by rune', () {
      app(assets: ['- assets/data/'], files: {
        'assets/data/units.csv': 'name,unit\nweight,≤ 2 kg\n',
      });
      expect(messages().single, allOf(contains('U+2264'), contains('units.csv')));
    });

    test('an SVG is checked only where it draws text', () {
      app(assets: ['- assets/plates/'], files: {
        'assets/plates/a.svg': '<svg><!-- drawn by Jörg → v2 -->'
            '<metadata>☃</metadata>'
            '<text x="1">Plain</text></svg>',
        'assets/plates/b.svg': '<svg><text>Next <tspan>&#x2192;</tspan>'
            '</text><text>&#8804; &amp; ok</text></svg>',
      });
      final m = messages();
      expect(m.join('\n'), allOf(contains('U+2192'), contains('U+2264')));
      expect(m.join('\n'), isNot(contains('U+2603')),
          reason: 'metadata and comments are never drawn');
      expect(m.join('\n'), isNot(contains('a.svg')));
    });

    test('binary assets are skipped, not decoded as text', () {
      app(assets: ['- assets/'], files: {
        'assets/icon.png': [0x89, 0x50, 0x4E, 0x47, 0x00, 0xE2, 0x86, 0x92],
        'assets/data.json': '{"a": "fine"}',
      });
      expect(messages(), isEmpty);
    });

    test('a directory entry ships only its direct files, as Flutter does', () {
      app(assets: ['- assets/data/'], files: {
        'assets/data/top.json': '{"a": "fine"}',
        'assets/data/nested/deep.json': '{"a": "→"}',
      });
      expect(messages(), isEmpty);
    });

    test('the "- path:" form of an asset entry is read', () {
      app(assets: ['- path: assets/data/canon.json'], files: {
        'assets/data/canon.json': '{"a": "→"}',
      });
      expect(messages().single, contains('U+2192'));
    });

    test('a text-named file that is not valid UTF-8 is a finding', () {
      app(assets: ['- assets/data/broken.json'], files: {
        'assets/data/broken.json': [0x7B, 0x22, 0xC3, 0x28, 0x22, 0x7D],
      });
      expect(messages(), contains(contains('UTF-8')));
    });
  });

  group('web builds', () {
    test('emoji in an asset are findings when the app ships a web build', () {
      app(assets: ['- assets/data/p.json'], web: true, files: {
        'assets/data/p.json': '{"avatar": "\u{1F464}"}',
      });
      expect(messages().single, contains('U+1F464'));
    });

    test('without web/index.html emoji keep their native exemption', () {
      app(assets: ['- assets/data/p.json'], files: {
        'assets/data/p.json': '{"avatar": "\u{1F464}"}',
      });
      expect(messages(), isEmpty);
    });
  });

  group('exemptions', () {
    test('an exempted asset is not checked', () {
      app(assets: ['- assets/LICENSE.txt'], files: {
        'assets/LICENSE.txt': 'Copyright → someone',
        'assets/data.json': '{}',
      });
      expect(
          messages(exemptions: {
            'assets/LICENSE.txt': 'shown by the platform licence page',
          }),
          contains(contains('no text assets')),
          reason: 'with the only text asset exempted, nothing was checked');
    });

    test('a blank reason is a finding', () {
      app(assets: ['- assets/data/'], files: {
        'assets/data/a.json': '{"a": "→"}',
        'assets/data/b.json': '{"b": "ok"}',
      });
      final m = messages(exemptions: {'assets/data/a.json': '  '});
      expect(m.join('\n'), contains('reason'));
    });

    test('an exemption naming no shipped text asset is a finding', () {
      app(assets: ['- assets/data/'], files: {
        'assets/data/b.json': '{"b": "ok"}',
      });
      final m = messages(exemptions: {'assets/data/gone.json': 'old'});
      expect(m.single, contains('assets/data/gone.json'));
    });
  });

  // PunctumTemporis's place names: drawn, and on purpose beyond the bundled
  // faces (Vietnamese and Latin Extended letters), relying on the engine's
  // fallback fonts. Exempting the file would leave nothing checked; the
  // allowance passes only the extended Latin letters and still checks the
  // rest of the file.
  group('Latin fallback allowances', () {
    const names = 'name\nHà Nội\nĐà Nẵng\n';
    test('extended Latin letters pass, and the file counts as checked', () {
      app(assets: ['- assets/data/'], files: {'assets/data/cities.csv': names});
      expect(messages(), isNotEmpty, reason: 'without it, ộ and ẵ are findings');
      expect(
          messages(fallback: {
            'assets/data/cities.csv': 'drawn through the fallback fonts',
          }),
          isEmpty);
    });

    test('anything else in that file is still checked', () {
      app(assets: ['- assets/data/'], files: {
        'assets/data/cities.csv': '${names}Tōkyō → 東京\n',
      });
      final m = messages(fallback: {'assets/data/cities.csv': 'fallback'});
      expect(m.join('\n'), allOf(contains('U+2192'), contains('U+6771')));
      expect(m.join('\n'), isNot(contains('U+1ED9')), reason: 'ộ is allowed');
    });

    test('a blank reason or a stale path is a finding', () {
      app(assets: ['- assets/data/'], files: {'assets/data/cities.csv': names});
      expect(messages(fallback: {'assets/data/cities.csv': ' '}).join('\n'),
          contains('reason'));
      expect(
          messages(fallback: {
            'assets/data/cities.csv': 'fallback',
            'assets/data/gone.csv': 'old',
          }).join('\n'),
          contains('assets/data/gone.csv'));
    });
  });

  group('the check cannot pass vacuously', () {
    test('no assets declared is a finding', () {
      app(assets: const []);
      expect(messages().single, contains('no text assets'));
    });

    test('only binary assets is a finding', () {
      app(assets: ['- assets/icon.png'], files: {
        'assets/icon.png': [0x89, 0x50, 0x00, 0x00],
      });
      expect(messages().single, contains('no text assets'));
    });

    // An empty placeholder or a drawing with no words is text on disk but
    // draws nothing, so it must not count as something checked.
    test('a .gitkeep or an SVG with no <text> checks nothing', () {
      app(assets: ['- assets/icons/', '- assets/icon/'], files: {
        'assets/icons/.gitkeep': '',
        'assets/icon/app_icon.svg': '<svg><path d="M0 0h1"/></svg>',
      });
      expect(messages().single, contains('no text assets'));
    });

    test('a declared asset that is not on disk is a finding', () {
      app(assets: ['- assets/data/canon.json', '- assets/data/b.json'],
          files: {'assets/data/b.json': '{"b": "ok"}'});
      expect(messages().single, contains('assets/data/canon.json'));
    });

    test('no readable bundled font is a finding', () {
      app(assets: ['- assets/data/b.json'], files: {'assets/data/b.json': '{}'});
      File('${root.path}/fonts/Fix-Regular.ttf').deleteSync();
      expect(messages().join('\n'), contains('font'));
    });
  });

  test('is wired as its own opt-in check, outside every default set', () {
    app(assets: ['- assets/data/canon.json'], files: {
      'assets/data/canon.json': '{"a": "→"}',
    });
    final results = collectFleetFindings(
      const FleetAppConfig(
        appId: 'fixture',
        styleTier: StyleTier.full,
        androidPermissions: {},
        checks: {FleetCheck.c7AssetText},
      ),
      root: root,
    );
    expect(results[FleetCheck.c7AssetText]!.single.check, 'C7-assetText');
    expect(FleetAppConfig.defaultChecks, isNot(contains(FleetCheck.c7AssetText)));
    expect(FleetAppConfig.withBundledFonts,
        isNot(contains(FleetCheck.c7AssetText)));
  });
}
