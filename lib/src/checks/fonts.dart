import 'dart:io';
import 'dart:typed_data';

import '../findings.dart';

const _check = 'C7-fonts';

/// C7 — every character the app prints must be one its own fonts can draw.
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
/// Two exemptions are real, not convenience. Emoji come from the platform's
/// colour font, never ours. A character class like `[\s$€£¥₹]` exists so a
/// pasted price parses — it is never drawn, and "fixing" it breaks input.
///
/// The check is written so it cannot pass by finding nothing: no declared
/// fonts, an unreadable font file, an implausibly small cmap, and an empty
/// `lib/` are all findings. A silent empty is the failure mode that would
/// make this whole check theatre.
List<ConformanceFinding> checkFontCoverage({required Directory root}) {
  final findings = <ConformanceFinding>[];

  final regulars = _regularWeightFiles(root);
  if (regulars.isEmpty) {
    return [
      const ConformanceFinding(
        _check,
        'no bundled font families declared in pubspec.yaml — either the '
        'app bundles type (and this check should read it) or it renders '
        'from the platform font (and should not enable C7)',
      ),
    ];
  }

  final coverage = <String, Set<int>>{};
  for (final entry in regulars.entries) {
    final file = File('${root.path}/${entry.value}');
    if (!file.existsSync()) {
      findings.add(ConformanceFinding(
        _check,
        'pubspec.yaml declares ${entry.value} for family ${entry.key} but '
        'the file is not on disk — the app would fall back to the platform '
        'font at runtime',
      ));
      continue;
    }
    coverage[entry.key] = _coveredBy(file.readAsBytesSync());
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

  final offenders = <String, Set<String>>{};
  for (final file in sources) {
    for (final line in file.readAsLinesSync()) {
      if (line.contains('RegExp(') || line.contains('// not-rendered')) {
        continue;
      }
      if (line.trimLeft().startsWith('//')) continue; // prose, never rendered
      for (final m in _quoted.allMatches(line)) {
        for (final r in m[0]!.runes) {
          if (r > 0x7F && !_isEmoji(r) && !drawable.contains(r)) {
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
      'draw it — it renders as a box',
    ));
  }
  return findings;
}

/// The code points every bundled family can draw, for app-specific
/// assertions the fleet check cannot know about (a target role's mark, a
/// month name table).
Set<int> bundledFontCoverage({required Directory root}) {
  final sets = <Set<int>>[];
  for (final path in _regularWeightFiles(root).values) {
    final file = File('${root.path}/$path');
    if (file.existsSync()) sets.add(_coveredBy(file.readAsBytesSync()));
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
List<String> undrawableIn(String text, Set<int> drawable) => [
      for (final r in text.runes)
        if (r > 0x7F && !_isEmoji(r) && !drawable.contains(r)) _describe(r),
    ];

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

/// family → the asset path of its regular weight, which is what body text
/// renders from. A family whose weights disagree would still box, but the
/// regular is where the bug always shows first.
Map<String, String> _regularWeightFiles(Directory root) {
  final pubspec = File('${root.path}/pubspec.yaml');
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
