import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oh_fleet_conformance/oh_fleet_conformance.dart';

import 'fonts_test.dart' show fontCovering;

const _goodBootstrap = '''
{{flutter_js}}
{{flutter_build_config}}
_flutter.loader.load({
  serviceWorkerSettings: {
    serviceWorkerVersion: {{flutter_service_worker_version}}
  },
  config: {
    canvasKitBaseUrl: "canvaskit/",
    fontFallbackBaseUrl: "/fonts/flutter-fallback/",
  },
});
''';

const _index = '''
<!DOCTYPE html>
<html><head><base href="\$FLUTTER_BASE_HREF"><title>Fixture</title>
<link rel="manifest" href="manifest.json"></head>
<body><script src="flutter_bootstrap.js" async></script></body></html>
''';

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('ohfc_web_'));
  tearDown(() => root.deleteSync(recursive: true));

  void write(String rel, String content) =>
      File('${root.path}/$rel')
        ..createSync(recursive: true)
        ..writeAsStringSync(content);

  /// A conformant app: a bundled Latin font, an index, a bootstrap.
  void app({
    String? bootstrap = _goodBootstrap,
    String index = _index,
    bool font = true,
  }) {
    write(
      'pubspec.yaml',
      'name: fixture\n\nflutter:\n'
          '${font ? '  fonts:\n    - family: Body\n      fonts:\n'
              '        - asset: assets/fonts/Body-Regular.ttf\n' : ''}',
    );
    if (font) {
      File('${root.path}/assets/fonts/Body-Regular.ttf')
        ..createSync(recursive: true)
        ..writeAsBytesSync(fontCovering([(0x20, 0x7E)]));
    }
    write('web/index.html', index);
    write('web/manifest.json', '{"name": "Fixture"}');
    if (bootstrap != null) write('web/flutter_bootstrap.js', bootstrap);
  }

  List<String> findings() =>
      checkWebSelfHosted(root: root).map((f) => f.message).toList();

  test('a self-hosted app with a bundled font passes', () {
    app();
    expect(findings(), isEmpty);
  });

  group('cannot pass by finding nothing', () {
    test('no web/ is a finding', () {
      write('pubspec.yaml', 'name: fixture\n');
      expect(findings().single, contains('no web/ directory'));
    });

    test('no index.html is a finding', () {
      app();
      File('${root.path}/web/index.html').deleteSync();
      expect(findings().single, contains('index.html is missing'));
    });

    test('no flutter_bootstrap.js is a finding (the default loads Roboto '
        'from fonts.gstatic.com)', () {
      app(bootstrap: null);
      expect(findings().single, contains('flutter_bootstrap.js is missing'));
    });

    test('a bootstrap that never calls the loader is a finding', () {
      app(bootstrap: '{{flutter_js}}\n{{flutter_build_config}}\n');
      expect(findings().single, contains('never calls _flutter.loader.load('));
    });

    test('no bundled text font is a finding', () {
      app(font: false);
      expect(findings().single, contains('no bundled text font'));
    });
  });

  group('the loader config', () {
    test('a missing key is a finding', () {
      app(bootstrap: _goodBootstrap.replaceFirst(
          'fontFallbackBaseUrl: "/fonts/flutter-fallback/",', ''));
      expect(findings().single,
          contains('does not set fontFallbackBaseUrl'));
    });

    test('a commented-out key does not count', () {
      app(bootstrap: _goodBootstrap.replaceFirst(
          'canvasKitBaseUrl: "canvaskit/",',
          '// canvasKitBaseUrl: "canvaskit/",\n/* fontFallbackBaseUrl: "x/" */'));
      expect(findings().single, contains('does not set canvasKitBaseUrl'));
    });

    test('an absolute or protocol-relative URL is a finding', () {
      app(bootstrap: _goodBootstrap
          .replaceFirst('"canvaskit/"', '"https://cdn.example/ck/"')
          .replaceFirst('"/fonts/flutter-fallback/"', '"//fonts.example/s/"'));
      expect(findings(), [
        contains('canvasKitBaseUrl to "https://cdn.example/ck/"'),
        contains('fontFallbackBaseUrl to "//fonts.example/s/"'),
      ]);
    });

    test('the fallback fonts must come from the fleet\'s shared path', () {
      // Every PWA is served from levitatingflyfisher.github.io/<App>/, and
      // the user site at that origin's root mirrors the engine's fallback
      // fonts once, under /fonts/flutter-fallback/. An app-relative path
      // resolves under /<App>/, where nothing is shipped: every missing
      // glyph is a box and a storm of 404 retries.
      expect(kFleetFontFallbackBaseUrl, '/fonts/flutter-fallback/');
      for (final local in ['fallback-fonts/', 'fonts/flutter-fallback/',
          '/fonts/flutter-fallback', '/fonts/']) {
        app(bootstrap: _goodBootstrap.replaceFirst(
            '"/fonts/flutter-fallback/"', '"$local"'));
        expect(findings().single, allOf(
          contains('fontFallbackBaseUrl to "$local"'),
          contains(kFleetFontFallbackBaseUrl),
        ), reason: local);
      }
    });

    test('only the load() call counts, not a key set earlier', () {
      app(bootstrap: 'var x = {fontFallbackBaseUrl: "local/"};\n'
          '${_goodBootstrap.replaceFirst('fontFallbackBaseUrl: "/fonts/flutter-fallback/",', '')}');
      expect(findings().single, contains('does not set fontFallbackBaseUrl'));
    });
  });

  group('Google hosts in web/', () {
    test('a Google Fonts stylesheet in index.html is two findings: the '
        'host and the cross-origin load', () {
      app(index: _index.replaceFirst('</head>',
          '<link href="https://fonts.googleapis.com/css2?family=Lora" '
              'rel="stylesheet"></head>'));
      final f = findings();
      expect(f, hasLength(2));
      expect(f, contains(contains('fonts.googleapis.com')));
      expect(f, contains(contains('from another origin')));
    });

    test('a gstatic URL in the bootstrap is a finding even in a comment', () {
      app(bootstrap: '// was: https://www.gstatic.com/flutter-canvaskit/\n'
          '$_goodBootstrap');
      expect(findings().single,
          allOf(contains('flutter_bootstrap.js:1'), contains('www.gstatic.com')));
    });

    test('a commented-out cross-origin script in index.html is not a load', () {
      app(index: _index.replaceFirst(
          '</head>', '<!-- <script src="https://cdn.example/x.js"></script> --></head>'));
      expect(findings(), isEmpty);
    });
  });
}
