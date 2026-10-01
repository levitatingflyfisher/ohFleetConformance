import 'dart:io';

import '../findings.dart';
import 'fonts.dart';

const _check = 'C13-webSelfHosted';

/// Where every fleet PWA's engine fetches its fallback fonts.
///
/// Every OpenHearth PWA is served from `levitatingflyfisher.github.io/<App>/`.
/// The user site at that origin's root (the `levitatingflyfisher.github.io`
/// repo, `OpenHearth/_ohsite_build`) mirrors the engine's on-demand fallback
/// fonts once, under this path, for the whole fleet: same origin for every
/// app, fetched only when text needs a glyph the bundled fonts lack.
/// Root-relative, so it resolves the same from any `/<App>/`.
const kFleetFontFallbackBaseUrl = '/fonts/flutter-fallback/';

/// C13 — the app's web build may load nothing from Google's CDNs.
///
/// `flutter build web` makes every visitor's browser fetch CanvasKit from
/// `www.gstatic.com` and the Roboto fallback font from `fonts.gstatic.com`
/// unless the app says otherwise. That is a third-party request on every
/// load from apps that promise privacy by default, and it breaks a
/// self-only Content-Security-Policy. WeatherGlass's privacy model said
/// "no third-party asset fetched at runtime" while its PWA did both.
///
/// The fix lives in the app's own `web/flutter_bootstrap.js`, which sets
/// `canvasKitBaseUrl` and `fontFallbackBaseUrl` in the loader config to
/// paths on the app's origin: CanvasKit relative (the build's own copy),
/// the fallback fonts exactly [kFleetFontFallbackBaseUrl] (one copy for
/// the fleet, so a glyph the bundled fonts lack still draws). That config wins whatever flags the build is
/// run with (`flutter build web` always copies CanvasKit into the build);
/// `--no-web-resources-cdn` in `deploy-pwa.sh` is the second layer, and
/// that script checks the built artifact too.
///
/// It cannot pass by finding nothing: an opted-in app with no `web/`, no
/// `web/index.html`, no `web/flutter_bootstrap.js`, no loader call, a
/// missing or absolute URL key, or no bundled text font is a finding. The
/// font rule is there because with the CDN Roboto gone, an app that
/// bundles no type (Lullaby) renders no text at all on the web.
///
/// Opt-in, outside every default set, like C7 onward.
List<ConformanceFinding> checkWebSelfHosted({required Directory root}) {
  final web = Directory('${root.path}/web');
  if (!web.existsSync()) {
    return const [
      ConformanceFinding(
        _check,
        'no web/ directory — nothing was checked; an app with no web build '
        'should not enable C13',
      ),
    ];
  }

  final findings = <ConformanceFinding>[];

  final index = File('${web.path}/index.html');
  if (!index.existsSync()) {
    findings.add(const ConformanceFinding(
      _check,
      'web/index.html is missing — nothing to check the page against',
    ));
  } else {
    for (final m
        in _absoluteSrcHref.allMatches(_stripHtmlComments(index.readAsStringSync()))) {
      findings.add(ConformanceFinding(
        _check,
        'web/index.html loads ${m.group(2)} from another origin — serve it '
        'from the app instead',
      ));
    }
  }

  // Every Google CDN host anywhere in web/'s text files, comments included:
  // a commented-out font link is one edit from shipping.
  final texts = web
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => _textExtensions.any(f.path.endsWith))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final f in texts) {
    final rel = f.path.substring(root.path.length + 1);
    final lines = f.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      for (final m in _googleHost.allMatches(lines[i])) {
        findings.add(ConformanceFinding(
          _check,
          '$rel:${i + 1} names ${m.group(0)} — a Google CDN the web build '
          'must not load from',
        ));
      }
    }
  }

  final bootstrap = File('${web.path}/flutter_bootstrap.js');
  if (!bootstrap.existsSync()) {
    findings.add(const ConformanceFinding(
      _check,
      'web/flutter_bootstrap.js is missing — Flutter then generates the '
      'default one, which loads the Roboto fallback font from '
      'fonts.gstatic.com (and CanvasKit from www.gstatic.com unless built '
      'with --no-web-resources-cdn). Add one that sets canvasKitBaseUrl and '
      'fontFallbackBaseUrl to paths on the app\'s origin',
    ));
  } else {
    final source = _stripJsComments(bootstrap.readAsStringSync());
    final call = source.lastIndexOf('_flutter.loader.load(');
    if (call < 0) {
      findings.add(const ConformanceFinding(
        _check,
        'web/flutter_bootstrap.js never calls _flutter.loader.load( — '
        'there is no loader config to check',
      ));
    } else {
      final config = source.substring(call);
      for (final key in const ['canvasKitBaseUrl', 'fontFallbackBaseUrl']) {
        final m = RegExp('["\']?$key["\']?\\s*:\\s*(["\'])(.*?)\\1')
            .firstMatch(config);
        if (m == null) {
          findings.add(ConformanceFinding(
            _check,
            'web/flutter_bootstrap.js does not set $key in its load() config '
            '— the engine default is Google\'s CDN',
          ));
        } else if (m.group(2)!.isEmpty ||
            RegExp(r'^([a-zA-Z][a-zA-Z0-9+.-]*:|//)').hasMatch(m.group(2)!)) {
          findings.add(ConformanceFinding(
            _check,
            'web/flutter_bootstrap.js sets $key to "${m.group(2)}" — it must '
            'be a relative path on the app\'s own origin',
          ));
        } else if (key == 'fontFallbackBaseUrl' &&
            m.group(2) != kFleetFontFallbackBaseUrl) {
          findings.add(ConformanceFinding(
            _check,
            'web/flutter_bootstrap.js sets fontFallbackBaseUrl to '
            '"${m.group(2)}" — it must be "$kFleetFontFallbackBaseUrl", the '
            'fleet\'s shared same-origin copy of the fallback fonts on '
            'levitatingflyfisher.github.io. Anywhere else nothing is '
            'shipped: a missing glyph draws as a box and the engine retries '
            'the 404 on every frame',
          ));
        }
      }
    }
  }

  final coverage = bundledFontCoverage(root: root);
  if (!'Aa0'.runes.every(coverage.contains)) {
    findings.add(const ConformanceFinding(
      _check,
      'no bundled text font draws basic Latin — once the CDN Roboto is '
      'gone, the web build would render no text. Bundle a font (or depend '
      'on openhearth_design) before enabling C13',
    ));
  }

  return findings;
}

const _textExtensions = ['.html', '.js', '.mjs', '.json', '.css', '.webmanifest'];

final _googleHost = RegExp(
  r'[a-zA-Z0-9.-]*\b(gstatic\.com|googleapis\.com|fonts\.google\.com|'
  r'google-analytics\.com|googletagmanager\.com)\b',
);

final _absoluteSrcHref = RegExp(
  r'''\b(src|href)\s*=\s*["']?((https?:)?//[^"'\s>]+)''',
  caseSensitive: false,
);

String _stripHtmlComments(String s) =>
    s.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');

/// Block and line comments out, string contents kept: a URL like
/// "canvaskit/" must survive, and `//` inside a string is not a comment.
String _stripJsComments(String s) {
  final out = StringBuffer();
  var i = 0;
  while (i < s.length) {
    final c = s[i];
    if (c == '"' || c == "'" || c == '`') {
      final start = i++;
      while (i < s.length && s[i] != c) {
        if (s[i] == '\\') i++;
        i++;
      }
      out.write(s.substring(start, i < s.length ? ++i : i));
    } else if (s.startsWith('/*', i)) {
      final end = s.indexOf('*/', i + 2);
      i = end < 0 ? s.length : end + 2;
    } else if (s.startsWith('//', i)) {
      final end = s.indexOf('\n', i);
      i = end < 0 ? s.length : end;
    } else {
      out.write(c);
      i++;
    }
  }
  return out.toString();
}
