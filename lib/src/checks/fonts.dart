import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../findings.dart';

const _check = 'C7-fonts';

/// C7 — every character the app prints must be one its bundled fonts can
/// draw: its own `fonts:` block plus `openhearth_design`'s package fonts.
///
/// An app that bundles its type does NOT fall back to a web font; that is
/// the point of bundling. So a character outside the bundled cmaps renders
/// as a tofu box, and whether it survives at all depends on an OS fallback
/// chain the fleet neither controls nor ships.
///
/// Peckish shipped a whole release printing `of □2200 kcal` because Lora
/// and Nunito have neither `≤` nor `≥`. The general form of that bug is a
/// source sweep, not a list of the strings someone remembered: the next em
/// dash or arrow gets caught the day it is typed.
///
/// Escapes are decoded first. `'Skip \u2192'` is plain ASCII in the source
/// but prints an arrow; StillLife's first web screen drew three boxes this
/// sweep could not see, because it read the raw runes. Raw strings
/// (`r'\u2192'`) print the backslash, so they are left alone.
///
/// One exemption is real, not convenience: a character class like
/// `[\s$€£¥₹]` exists so a pasted price parses — it is never drawn, and
/// "fixing" it breaks input.
///
/// Emoji are exempt only for an app with no web build. On Android they come
/// from the platform's colour font. On the web they do not: since C13 the
/// engine fetches fallback fonts from the fleet's shared same-origin copy
/// ([kFleetFontFallbackBaseUrl]). That covers what users type, but the
/// app's own copy should not depend on it: the colour-emoji splits are
/// hundreds of KB each, fetched on first draw, and an installed PWA used
/// offline (or served anywhere without that copy) draws a box and re-requests
/// the missing font on every frame. An app with `web/index.html` therefore
/// has no emoji exemption, and the zero-width joiner and variation selectors
/// that glue emoji together are findings too.
///
/// The check is written so it cannot pass by finding nothing: no declared
/// fonts, an unreadable font file, an implausibly small cmap, and an empty
/// `lib/` are all findings. A silent empty is the failure mode that would
/// make this whole check theatre.
List<ConformanceFinding> checkFontCoverage({required Directory root}) {
  final findings = <ConformanceFinding>[];

  final faces = _bundledFaces(root);
  if (faces.isEmpty) {
    return [
      const ConformanceFinding(
        _check,
        'no bundled font families declared in pubspec.yaml or in '
        'openhearth_design\'s package fonts — either the app bundles type '
        '(and this check should read it) or it renders from the platform '
        'font (and should not enable C7)',
      ),
    ];
  }

  final coverage = <String, Set<int>>{};
  for (final face in faces) {
    if (!face.file.existsSync()) {
      findings.add(ConformanceFinding(
        _check,
        '${face.declaredBy} declares ${face.asset} for family ${face.family} '
        'but the file is not on disk — the app would fall back to the '
        'platform font at runtime',
      ));
      continue;
    }
    coverage[face.family] = _coveredBy(face.file.readAsBytesSync());
  }
  if (coverage.isEmpty) return findings;

  // Text can land in any bundled family, so a character is only safe when
  // every one of them can draw it.
  var drawable = coverage.values.first;
  for (final c in coverage.values.skip(1)) {
    drawable = drawable.intersection(c);
  }

  if (drawable.length <= 200) {
    findings.add(ConformanceFinding(
      _check,
      'the bundled fonts cover only ${drawable.length} shared code points — '
      'a real body font covers hundreds, so the cmap parse or the font '
      'files are wrong and every check below would pass vacuously',
    ));
  }
  if (!drawable.contains(0x00B7)) {
    findings.add(const ConformanceFinding(
      _check,
      'the bundled fonts cannot draw · (U+00B7), which the fleet\'s date '
      'labels use — either the fonts changed or a family was added that '
      'is narrower than the rest',
    ));
  }

  final lib = Directory('${root.path}/lib');
  final sources = lib.existsSync()
      ? lib
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart') && !f.path.endsWith('.g.dart'))
          .toList()
      : <File>[];
  if (sources.isEmpty) {
    findings.add(const ConformanceFinding(
      _check,
      'no Dart sources found under lib/ — nothing was swept, which is not '
      'the same as nothing being wrong',
    ));
    return findings;
  }

  final web = File('${root.path}/web/index.html').existsSync();
  final offenders = <String, Set<String>>{};
  for (final file in sources) {
    for (final line in file.readAsLinesSync()) {
      if (line.contains('RegExp(') || line.contains('// not-rendered')) {
        continue;
      }
      if (line.trimLeft().startsWith('//')) continue; // prose, never rendered
      for (final m in _quoted.allMatches(line)) {
        final raw = m.start > 0 && (line[m.start - 1] == 'r' ||
            line[m.start - 1] == 'R');
        final printed = raw ? m[0]! : _decodeEscapes(m[0]!);
        for (final r in printed.runes) {
          if (_undrawable(r, drawable, web: web)) {
            offenders
                .putIfAbsent(_describe(r), () => <String>{})
                .add(_relative(file.path, root));
          }
        }
      }
    }
  }

  for (final e in offenders.entries) {
    findings.add(ConformanceFinding(
      _check,
      '${e.key} is printed in ${e.value.join(', ')} but no bundled font can '
      'draw it — it renders as a box'
      '${web ? ' (this app ships a web build, where no platform font fills '
          'the gap — emoji included)' : ''}',
    ));
  }
  return findings;
}

/// The code points every bundled family can draw, for app-specific
/// assertions the fleet check cannot know about (a target role's mark, a
/// month name table).
Set<int> bundledFontCoverage({required Directory root}) {
  final sets = <Set<int>>[];
  for (final face in _bundledFaces(root)) {
    if (face.file.existsSync()) {
      sets.add(_coveredBy(face.file.readAsBytesSync()));
    }
  }
  if (sets.isEmpty) return const {};
  var out = sets.first;
  for (final s in sets.skip(1)) {
    out = out.intersection(s);
  }
  return out;
}

/// The characters of [text] that [drawable] cannot render, described for a
/// failure message. Empty means the string is safe to print.
///
/// Pass `web: true` for text an app's web build prints: there the emoji
/// exemption does not hold (see [checkFontCoverage]).
List<String> undrawableIn(String text, Set<int> drawable,
        {bool web = false}) =>
    [
      for (final r in text.runes)
        if (_undrawable(r, drawable, web: web)) _describe(r),
    ];

bool _undrawable(int r, Set<int> drawable, {required bool web}) =>
    r > 0x7F && (web || !_isEmoji(r)) && !drawable.contains(r);

/// What a quoted (non-raw) Dart literal prints: `\uXXXX`, `\u{X…}`, `\xHH`
/// and the single-character escapes resolved. Code units are assembled
/// first so an escaped surrogate pair (`\uD83D\uDC64`) becomes one emoji,
/// not two lone surrogates.
String _decodeEscapes(String literal) {
  final units = <int>[];
  final s = literal;
  var i = 0;
  while (i < s.length) {
    final c = s.codeUnitAt(i);
    if (c != 0x5C || i + 1 >= s.length) {
      units.add(c);
      i++;
      continue;
    }
    final e = s[i + 1];
    int? cp;
    var consumed = 2;
    if (e == 'u' && i + 2 < s.length && s[i + 2] == '{') {
      final close = s.indexOf('}', i + 3);
      if (close > 0) {
        cp = int.tryParse(s.substring(i + 3, close), radix: 16);
        consumed = close - i + 1;
      }
    } else if (e == 'u' && i + 6 <= s.length) {
      cp = int.tryParse(s.substring(i + 2, i + 6), radix: 16);
      consumed = 6;
    } else if (e == 'x' && i + 4 <= s.length) {
      cp = int.tryParse(s.substring(i + 2, i + 4), radix: 16);
      consumed = 4;
    }
    if (cp != null) {
      if (cp > 0xFFFF) {
        final v = cp - 0x10000;
        units
          ..add(0xD800 + (v >> 10))
          ..add(0xDC00 + (v & 0x3FF));
      } else {
        units.add(cp);
      }
    } else {
      // \n, \', \\, \$ and friends print ASCII; the second character
      // stands for itself as far as glyph coverage goes.
      units.add(s.codeUnitAt(i + 1));
      consumed = 2;
    }
    i += consumed;
  }
  return String.fromCharCodes(units);
}

final _quoted = RegExp(r"'([^'\\\n]|\\.)*'|" r'"([^"\\\n]|\\.)*"');

String _describe(int r) =>
    '${String.fromCharCode(r)} (U+${r.toRadixString(16).toUpperCase().padLeft(4, '0')})';

String _relative(String path, Directory root) =>
    path.startsWith(root.path) ? path.substring(root.path.length + 1) : path;

/// True for code points a system emoji font renders regardless of what the
/// app bundles: the pictographic planes, plus the zero-width joiner and
/// variation selectors that glue emoji sequences together.
bool _isEmoji(int r) =>
    r >= 0x1F000 || r == 0x200D || (r >= 0xFE00 && r <= 0xFE0F);

/// Packages whose pubspec `fonts:` land in every dependent app's
/// FontManifest under `packages/<name>/<Family>`. ohStyle ships Lora and
/// Nunito this way, so an app that dropped its own copies still bundles them.
const _fontPackages = ['openhearth_design'];

/// One family's regular-weight face, wherever it is declared.
class _Face {
  const _Face(this.family, this.asset, this.file, this.declaredBy);

  /// The name text asks for: bare for the app's own, prefixed for a
  /// package's (`packages/openhearth_design/Lora`).
  final String family;
  final String asset;
  final File file;
  final String declaredBy;
}

/// Every bundled family's regular face: the app's own `fonts:` block plus
/// each [_fontPackages] dependency's. Both [checkFontCoverage] and
/// [bundledFontCoverage] read this, so they cannot disagree about what the
/// app ships.
List<_Face> _bundledFaces(Directory root) {
  final faces = <_Face>[
    for (final e in _regularWeightFiles(File('${root.path}/pubspec.yaml'))
        .entries)
      _Face(e.key, e.value, File('${root.path}/${e.value}'), 'pubspec.yaml'),
  ];
  for (final pkg in _fontPackages) {
    final pkgRoot = _packageRoot(root, pkg);
    if (pkgRoot == null) continue;
    for (final e
        in _regularWeightFiles(File('${pkgRoot.path}/pubspec.yaml')).entries) {
      faces.add(_Face('packages/$pkg/${e.key}', e.value,
          File('${pkgRoot.path}/${e.value}'), "$pkg's pubspec.yaml"));
    }
  }
  return faces;
}

/// Where [package] lives for this app. `.dart_tool/package_config.json` is
/// authoritative when present (it is what the build resolves); a package it
/// does not list is not a dependency. Without it — before `pub get` — the
/// app's own pubspec `path:` dependency is the only honest source.
Directory? _packageRoot(Directory root, String package) {
  final config = File('${root.path}/.dart_tool/package_config.json');
  if (config.existsSync()) {
    try {
      final json = jsonDecode(config.readAsStringSync()) as Map<String, dynamic>;
      for (final p in (json['packages'] as List).cast<Map<String, dynamic>>()) {
        if (p['name'] != package) continue;
        final uri = Uri.file(config.absolute.path).resolve(p['rootUri'] as String);
        return Directory(uri.toFilePath());
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  final pubspec = File('${root.path}/pubspec.yaml');
  if (!pubspec.existsSync()) return null;
  final lines = pubspec.readAsLinesSync();
  for (var i = 0; i < lines.length - 1; i++) {
    if (!RegExp('^\\s+$package:\\s*\$').hasMatch(lines[i])) continue;
    final path = RegExp(r'^\s+path:\s*(\S+)').firstMatch(lines[i + 1]);
    if (path == null) return null;
    final dir = path.group(1)!;
    return Directory(dir.startsWith('/') ? dir : '${root.path}/$dir');
  }
  return null;
}

/// family → the asset path of its regular weight, which is what body text
/// renders from, as declared in [pubspec]. A family whose weights disagree
/// would still box, but the regular is where the bug always shows first.
Map<String, String> _regularWeightFiles(File pubspec) {
  if (!pubspec.existsSync()) return const {};
  final out = <String, String>{};
  String? family;
  String? asset;
  var isRegular = true;
  var inFonts = false;

  void flush() {
    final f = family;
    final a = asset;
    if (f != null && a != null && isRegular) out.putIfAbsent(f, () => a);
    asset = null;
    isRegular = true;
  }

  for (final line in pubspec.readAsLinesSync()) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
    if (RegExp(r'^\s*fonts:\s*$').hasMatch(line) && line.startsWith('  ')) {
      inFonts = true;
      continue;
    }
    if (!inFonts) continue;
    // A key back at the top level ends the flutter: block entirely.
    if (!line.startsWith(' ')) break;

    final fam = RegExp(r'^\s*-\s*family:\s*(\S.*)$').firstMatch(line);
    if (fam != null) {
      flush();
      family = fam.group(1)!.trim();
      continue;
    }
    final ast = RegExp(r'^\s*-\s*asset:\s*(\S.*)$').firstMatch(line);
    if (ast != null) {
      flush();
      asset = ast.group(1)!.trim();
      continue;
    }
    if (RegExp(r'^\s*style:').hasMatch(line)) isRegular = false;
    final w = RegExp(r'^\s*weight:\s*(\d+)').firstMatch(line);
    if (w != null && w.group(1) != '400') isRegular = false;
  }
  flush();
  return out;
}

/// Every Unicode code point a font's cmap can draw.
///
/// Format 4 only: it is the BMP mapping every text font ships, and the
/// characters that bite (arrows, maths, currency, dashes) all live there.
Set<int> _coveredBy(List<int> data) {
  final bytes = ByteData.view(Uint8List.fromList(data).buffer);
  if (data.length < 12) return const {};

  final numTables = bytes.getUint16(4);
  int? cmapOffset;
  for (var i = 0; i < numTables; i++) {
    final rec = 12 + 16 * i;
    if (rec + 12 > data.length) break;
    final tag = String.fromCharCodes(data.sublist(rec, rec + 4));
    if (tag == 'cmap') cmapOffset = bytes.getUint32(rec + 8);
  }
  if (cmapOffset == null || cmapOffset + 4 > data.length) return const {};

  final covered = <int>{};
  final numSubtables = bytes.getUint16(cmapOffset + 2);
  for (var i = 0; i < numSubtables; i++) {
    final rec = cmapOffset + 4 + 8 * i;
    if (rec + 8 > data.length) break;
    final subtable = cmapOffset + bytes.getUint32(rec + 4);
    if (subtable + 14 > data.length) continue;
    if (bytes.getUint16(subtable) != 4) continue;
    final segCount = bytes.getUint16(subtable + 6) ~/ 2;
    final endsAt = subtable + 14;
    final startsAt = endsAt + segCount * 2 + 2;
    if (startsAt + segCount * 2 > data.length) continue;
    for (var s = 0; s < segCount; s++) {
      final end = bytes.getUint16(endsAt + s * 2);
      final start = bytes.getUint16(startsAt + s * 2);
      if (end == 0xFFFF) continue; // the required terminator segment
      for (var c = start; c <= end; c++) {
        covered.add(c);
      }
    }
  }
  return covered;
}
