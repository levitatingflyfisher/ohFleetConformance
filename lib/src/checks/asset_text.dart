import 'dart:convert';
import 'dart:io';

import '../findings.dart';
import 'fonts.dart';

const _check = 'C7-assetText';

/// C7's second half (opt-in, `FleetCheck.c7AssetText`): every character an
/// app's bundled text ASSETS put on screen must be one its bundled fonts
/// can draw.
///
/// C7 sweeps the string literals in `lib/`. It never saw the words that
/// live in data files: Mantle's deck titles ("Nō") and canon (間), Lilt's
/// name list, a Trellis course. Mantle wrote its own content test to cover
/// the gap; this is that test made fleet-wide, so the next app with a JSON
/// deck is covered the day it ships one.
///
/// What counts as drawn text, per file (read from the pubspec's `assets:`,
/// where a directory entry ships only its direct files, as Flutter does):
/// - JSON (sniffed by content, so `.ohcourse` counts): every string VALUE,
///   escapes resolved by the decoder. Keys are identifiers and never drawn.
/// - SVG / XML: only `<text>` (and its `<tspan>`s), with character
///   references decoded. Comments, metadata and editor attributes are not
///   drawn, and scanning them would force whole-file exemptions that hollow
///   the check out.
/// - Any other UTF-8 file (CSV, TXT, Markdown): every character.
/// - Binary files (a NUL byte, or not UTF-8 under a non-text name) are
///   skipped. A text-named file that is not UTF-8 is a finding.
///
/// The web rule is C7's: an app with `web/index.html` gets no emoji
/// exemption.
///
/// It cannot pass by finding nothing: no readable bundled font, a declared
/// asset missing on disk, and no text asset at all are findings. An app
/// with nothing to scan should not enable the check. [exemptions] maps an
/// asset path to the reason it is never drawn (a licence the platform page
/// shows); a blank reason, or a path that is not a shipped text asset, is a
/// finding.
///
/// [latinFallback] maps an asset path to the reason its extended Latin
/// letters (Latin Extended-A and -B, IPA, combining marks, Latin Extended
/// Additional: U+0100–U+02AF, U+0300–U+036F, U+1E00–U+1EFF) may lie beyond
/// the bundled faces: text the app draws on purpose through the engine's
/// fallback fonts (the phone's system fonts natively, the shared Noto
/// mirror on the web), such as a list of place names. Every other character
/// in that file is still checked, and the file counts as checked. A blank
/// reason or a stale path is a finding.
List<ConformanceFinding> checkAssetTextCoverage({
  required Directory root,
  Map<String, String> exemptions = const {},
  Map<String, String> latinFallback = const {},
}) {
  final findings = <ConformanceFinding>[];

  final drawable = bundledFontCoverage(root: root);
  if (drawable.length <= 200) {
    return [
      ConformanceFinding(
        _check,
        'no readable bundled font (${drawable.length} shared code points) — '
        'every asset would pass vacuously; fix the font declaration (C7 '
        'says more)',
      ),
    ];
  }

  final files = <File>[];
  for (final entry in _assetEntries(File('${root.path}/pubspec.yaml'))) {
    final path = '${root.path}/$entry';
    if (entry.endsWith('/')) {
      final dir = Directory(path);
      if (!dir.existsSync()) {
        findings.add(_missing(entry));
        continue;
      }
      files.addAll(dir.listSync().whereType<File>());
    } else {
      final f = File(path);
      if (!f.existsSync()) {
        findings.add(_missing(entry));
        continue;
      }
      files.add(f);
    }
  }

  final web = File('${root.path}/web/index.html').existsSync();
  final seen = <String>{};
  final checked = <String>{};
  final textAssets = <String>{};
  final offenders = <String, Set<String>>{};

  for (final file in files) {
    final rel = file.path.substring(root.path.length + 1);
    if (!seen.add(rel)) continue;
    final bytes = file.readAsBytesSync();
    final textNamed = _textExtensions.any(rel.toLowerCase().endsWith);
    if (bytes.contains(0)) continue; // binary
    final String content;
    try {
      content = utf8.decode(bytes);
    } on FormatException {
      if (textNamed) {
        findings.add(ConformanceFinding(
          _check,
          '$rel is not valid UTF-8 — Flutter would decode it wrongly and '
          'its text could not be checked',
        ));
      }
      continue;
    }
    textAssets.add(rel);
    if (exemptions.containsKey(rel)) continue;

    // Only a file that draws words counts as checked: an empty .gitkeep or
    // an SVG with no <text> is text on disk but puts nothing on screen.
    final drawn = _drawnText(content).where((s) => s.trim().isNotEmpty);
    if (drawn.isEmpty) continue;
    checked.add(rel);
    final fallback = latinFallback.containsKey(rel);
    for (final s in drawn) {
      final text = fallback
          ? String.fromCharCodes(s.runes.where((r) => !_extendedLatin(r)))
          : s;
      for (final d in undrawableIn(text, drawable, web: web)) {
        offenders.putIfAbsent(d, () => <String>{}).add(rel);
      }
    }
  }

  for (final e in exemptions.entries) {
    if (e.value.trim().isEmpty) {
      findings.add(ConformanceFinding(
        _check,
        'the exemption for ${e.key} gives no reason — say why its text is '
        'never drawn, or drop the exemption',
      ));
    }
    if (!textAssets.contains(e.key)) {
      findings.add(ConformanceFinding(
        _check,
        'the exemption for ${e.key} names no shipped text asset — it is '
        'stale; remove it',
      ));
    }
  }

  for (final e in latinFallback.entries) {
    if (e.value.trim().isEmpty) {
      findings.add(ConformanceFinding(
        _check,
        'the Latin fallback allowance for ${e.key} gives no reason — say how '
        'its extended letters are drawn, or drop it',
      ));
    }
    if (!textAssets.contains(e.key)) {
      findings.add(ConformanceFinding(
        _check,
        'the Latin fallback allowance for ${e.key} names no shipped text '
        'asset — it is stale; remove it',
      ));
    }
  }

  if (checked.isEmpty) {
    findings.add(const ConformanceFinding(
      _check,
      'no text assets were checked (none declared under flutter: assets:, '
      'none that draws any words, or all exempted) — an app with nothing to '
      'scan should not enable C7-assetText',
    ));
  }

  for (final e in offenders.entries) {
    findings.add(ConformanceFinding(
      _check,
      '${e.key} is in ${(e.value.toList()..sort()).join(', ')} but no '
      'bundled font can draw it — it renders as a box'
      '${web ? ' (this app ships a web build: emoji included)' : ''}',
    ));
  }
  return findings;
}

/// Extended Latin letters a [latinFallback] allowance passes.
bool _extendedLatin(int r) =>
    (r >= 0x100 && r <= 0x2AF) ||
    (r >= 0x300 && r <= 0x36F) ||
    (r >= 0x1E00 && r <= 0x1EFF);

ConformanceFinding _missing(String entry) => ConformanceFinding(
      _check,
      'pubspec.yaml declares the asset $entry but it is not on disk — the '
      'build would fail, and nothing in it was checked',
    );

const _textExtensions = [
  '.json', '.txt', '.md', '.csv', '.tsv', '.svg', '.xml', '.arb', '.yaml',
  '.yml', '.html',
];

/// The strings [content] puts on screen, by sniffed format.
Iterable<String> _drawnText(String content) {
  final trimmed = content.trimLeft();
  if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
    try {
      return _jsonValues(jsonDecode(content)).toList();
    } on FormatException {
      // Not JSON after all: fall through to plain text.
    }
  }
  if (trimmed.startsWith('<')) {
    return [
      for (final m in _textElement.allMatches(content))
        _decodeReferences(m.group(1)!.replaceAll(_tag, '')),
    ];
  }
  return [content];
}

Iterable<String> _jsonValues(Object? o) sync* {
  if (o is String) {
    yield o;
  } else if (o is List) {
    for (final x in o) {
      yield* _jsonValues(x);
    }
  } else if (o is Map) {
    for (final v in o.values) {
      yield* _jsonValues(v);
    }
  }
}

final _textElement =
    RegExp(r'<(?:svg:)?text\b[^>]*>([\s\S]*?)</(?:svg:)?text>');
final _tag = RegExp(r'<[^>]*>');
final _reference = RegExp(r'&(#x[0-9a-fA-F]+|#[0-9]+|amp|lt|gt|quot|apos);');

String _decodeReferences(String s) => s.replaceAllMapped(_reference, (m) {
      final r = m.group(1)!;
      if (r.startsWith('#x')) {
        return String.fromCharCode(int.parse(r.substring(2), radix: 16));
      }
      if (r.startsWith('#')) return String.fromCharCode(int.parse(r.substring(1)));
      return const {'amp': '&', 'lt': '<', 'gt': '>', 'quot': '"', 'apos': "'"}[r]!;
    });

/// The `flutter: assets:` entries of [pubspec], in either form
/// (`- path/` or `- path: path/`).
List<String> _assetEntries(File pubspec) {
  if (!pubspec.existsSync()) return const [];
  final out = <String>[];
  var inFlutter = false;
  var inAssets = false;
  for (final line in pubspec.readAsLinesSync()) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
    if (!line.startsWith(' ')) {
      inFlutter = line.startsWith('flutter:');
      inAssets = false;
      continue;
    }
    if (!inFlutter) continue;
    final indent = line.length - line.trimLeft().length;
    if (indent <= 2) {
      inAssets = trimmed == 'assets:';
      continue;
    }
    if (!inAssets) continue;
    final m = RegExp(r'^-\s*(?:path:\s*)?(\S+)\s*$').firstMatch(trimmed);
    if (m != null) out.add(m.group(1)!.replaceAll(RegExp('''^['"]|['"]\$'''), ''));
  }
  return out;
}
