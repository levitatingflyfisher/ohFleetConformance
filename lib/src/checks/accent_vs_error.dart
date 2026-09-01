import 'dart:io';

import 'package:flutter/material.dart' show Brightness, Color, ColorScheme;

import '../color_science.dart';
import '../findings.dart';
import '../source_scan.dart';
import 'style.dart' show canonicalTokensByNameFrom;

const _check = 'C12-accentVsError';

/// Minimum CIEDE2000 between an accent and its theme's error colour.
///
/// The operator's colour ruling (2026-09-26, Q9): red may be BOTH warmth
/// and error. What keeps them apart is not hue but the style guide's rule
/// that an error is colour + icon + word — take the colour away and it
/// still reads as urgent. So C12 does not demand that the accent look
/// unlike red; it fails only when the accent is effectively the SAME
/// colour as the error, where the pairing rule is all that is left.
/// ΔE00 ≈ 2.3 is one just-noticeable difference and ~10 is the
/// conventional "different at a glance" level; 12 sits just past it.
/// ohStyle 0.7.0's own warmth clears it (light 14.1, dark 16.6).
const double accentMinDeltaE = 12;

/// Dichromat simulation (Machado 2009, severity 1.0, protan/deutan/
/// tritan) is reported as a NOTE on a failing finding, never a failure of
/// its own: under the ruling, a colour-blind viewer tells error from
/// warmth by the icon and the word, which is exactly why they are
/// mandatory. Pairs merging below this ΔE00 are named in the note.
const double accentCvdNoteBelow = 10;

/// One accent an app paints as its primary, in one theme brightness —
/// the value actually rendered (after any `fromSeed` tone mapping), not a
/// seed. Record every accent the user can end up with, including
/// user-selectable presets.
class FleetAccent {
  final Brightness brightness;
  final int argb;
  final String? label;
  const FleetAccent.light(this.argb, {this.label})
      : brightness = Brightness.light;
  const FleetAccent.dark(this.argb, {this.label})
      : brightness = Brightness.dark;
}

/// C12 — the accent must not look like an error.
///
/// ohStyle's colour language keeps warmth (brand, the one primary action)
/// and urgency (error, destructive) apart. An app accent drifting toward
/// the error red makes every primary button read as a warning — and for a
/// colour-blind parent the two may be the same colour.
///
/// **Reference.** The urgency role of each `OhColorRoles` set in the
/// canonical design package (`color_roles.dart`, resolved through
/// `colors.dart`): `light` pairs with light accents, every other set
/// (`hearthDark`, `night`) with dark accents. The check follows ohStyle:
/// change urgency there and C12 measures against the new value.
///
/// **Accents.** `FleetAppConfig.accentColors` when recorded (detection is
/// then skipped entirely). Otherwise detected from authored `lib/` code:
///  * `ColorScheme.fromSeed(seedColor:)` — the RENDERED primary, computed
///    with Flutter's own `ColorScheme.fromSeed`; an explicit `primary:` or
///    a chained `.copyWith(primary:)` wins; `brightness:` picks the theme
///    (a non-literal brightness means both);
///  * `ColorScheme(`/`.light(`/`.dark(` with `primary:`;
///  * `OhTheme.light/hearthDark/night(appAccent:)`, or that set's warmth
///    role when no `appAccent` is given.
/// Values resolve through `Color(0x…)` literals, `OhColors.*`, and
/// `const`/`final` declarations in `lib/` (`AppColors.sky`, a same-file
/// `accent`). Anything else — a parameter, a user preference — is a
/// finding asking the app to record `accentColors`; that is how
/// user-selectable presets (PunctumTemporis's `accentPresets`) get judged.
///
/// **Rule.** Each accent vs the urgency of its own brightness:
/// CIEDE2000 ≥ [accentMinDeltaE]. A failing finding also notes how the
/// pair fares under each simulated dichromacy ([accentCvdNoteBelow]); that
/// note never fails on its own. Cross-theme pairs never share a screen
/// and are not compared.
///
/// Cannot pass by finding nothing: a missing design package, no urgency
/// role parsed, an accent whose theme brightness has no urgency role, and
/// no accent found or declared are all findings.
List<ConformanceFinding> checkAccentVsError({
  required Directory root,
  required Directory designPackage,
  List<FleetAccent> declared = const [],
}) {
  final Map<String, int> tokens;
  try {
    tokens = canonicalTokensByNameFrom(designPackage);
  } on StateError catch (e) {
    return [ConformanceFinding(_check, e.message)];
  }
  final roles = _readRoles(designPackage, tokens);
  final urgencies = <Brightness, Map<int, String>>{};
  for (final r in roles.entries) {
    final u = r.value.urgency;
    if (u == null) continue;
    urgencies
        .putIfAbsent(_roleBrightness(r.key), () => {})
        .putIfAbsent(u, () => 'OhColorRoles.${r.key}.urgency');
  }
  if (urgencies.isEmpty) {
    return [
      ConformanceFinding(
        _check,
        'no urgency role parsed from ${designPackage.path}/lib/src/'
        'color_roles.dart — there is no error colour to measure against, '
        'which is not the same as the accent being distinct',
      ),
    ];
  }

  final findings = <ConformanceFinding>[];
  final accents = <_Accent>[];
  if (declared.isNotEmpty) {
    for (final d in declared) {
      accents.add(_Accent(d.brightness, d.argb,
          'declared in FleetAppConfig.accentColors${d.label == null ? '' : ' (${d.label})'}'));
    }
  } else {
    _detect(root, tokens, roles, accents, findings);
    if (accents.isEmpty && findings.isEmpty) {
      return const [
        ConformanceFinding(
          _check,
          'no accent found in lib/ (no ColorScheme.fromSeed/ColorScheme '
          'primary/OhTheme call) and none recorded in '
          'FleetAppConfig.accentColors — nothing was measured',
        ),
      ];
    }
  }

  final seen = <String>{};
  for (final a in accents) {
    if (!seen.add('${a.brightness}:${a.argb}')) continue;
    final against = urgencies[a.brightness];
    if (against == null) {
      findings.add(ConformanceFinding(
        _check,
        'accent ${_hex(a.argb)} (${a.brightness.name}; ${a.source}) has no '
        '${a.brightness.name} urgency role in color_roles.dart to be measured '
        'against — unmeasured is not the same as distinct',
      ));
      continue;
    }
    for (final u in against.entries) {
      final de = ciede2000(labFromArgb(a.argb), labFromArgb(u.key));
      final what = 'accent ${_hex(a.argb)} (${a.brightness.name}; '
          '${a.source}) vs ohStyle ${u.value} ${_hex(u.key)}';
      if (de >= accentMinDeltaE) continue;
      final cvdNotes = [
        for (final cvd in ColorVisionDeficiency.values)
          (
            cvd.name,
            ciede2000(labFromArgb(simulateCvd(a.argb, cvd)),
                labFromArgb(simulateCvd(u.key, cvd)))
          ),
      ];
      final merged = cvdNotes.where((n) => n.$2 < accentCvdNoteBelow);
      findings.add(ConformanceFinding(
        _check,
        '$what: CIEDE2000 ${de.toStringAsFixed(1)} < '
        '${accentMinDeltaE.toStringAsFixed(0)} — the accent is effectively '
        'the error colour; move it away from urgency. Note (informational, '
        'colour-blind simulation): '
        '${cvdNotes.map((n) => '${n.$1} ${n.$2.toStringAsFixed(1)}').join(', ')}'
        '${merged.isEmpty ? '' : ' — merged for ${merged.map((n) => n.$1).join(', ')}'}',
      ));
    }
  }
  return findings;
}

class _Accent {
  final Brightness brightness;
  final int argb;
  final String source;
  _Accent(this.brightness, this.argb, this.source);
}

class _Role {
  int? urgency;
  int? warmth;
}

Brightness _roleBrightness(String roleSet) =>
    roleSet == 'light' ? Brightness.light : Brightness.dark;

String _hex(int argb) =>
    '0x${argb.toRadixString(16).toUpperCase().padLeft(8, '0')}';

Map<String, _Role> _readRoles(Directory design, Map<String, int> tokens) {
  final file = File('${design.path}/lib/src/color_roles.dart');
  if (!file.existsSync()) return const {};
  final src = ScannedSource('color_roles.dart', file.readAsStringSync());
  final roles = <String, _Role>{};
  final decl = RegExp(r'static\s+const\s+(\w+)\s*=\s*OhColorRoles\s*\(');
  for (final m in decl.allMatches(src.structure)) {
    final open = m.end - 1;
    final close = matchingClose(src.structure, open);
    if (close == null) continue;
    int? token(String label) {
      final arg = namedArgument(src.structure, open, close, label);
      if (arg == null) return null;
      final t = RegExp(r'^\s*OhColors\.(\w+)\s*$')
          .firstMatch(src.structure.substring(arg.start, arg.end));
      return t == null ? null : tokens[t.group(1)!];
    }

    roles[m.group(1)!] = _Role()
      ..urgency = token('urgency')
      ..warmth = token('warmth');
  }
  return roles;
}

void _detect(
  Directory root,
  Map<String, int> tokens,
  Map<String, _Role> roles,
  List<_Accent> accents,
  List<ConformanceFinding> findings,
) {
  final sources = ScannedSource.under(root);

  int? resolve(String expr, ScannedSource src, [int depth = 0]) {
    if (depth > 4) return null;
    var e = expr.trim();
    if (e.startsWith('const ')) e = e.substring(6).trim();
    final lit = RegExp(r'^Color\(\s*0x([0-9A-Fa-f]{8})\s*\)$').firstMatch(e);
    if (lit != null) return int.parse(lit.group(1)!, radix: 16);
    final oh = RegExp(r'^OhColors\.(\w+)$').firstMatch(e);
    if (oh != null) return tokens[oh.group(1)!];
    RegExp declOf(String name) => RegExp(
        '(?:const|final)\\s+(?:Color\\s+)?${RegExp.escape(name)}\\s*=\\s*([^;]+);');
    final member = RegExp(r'^[A-Z]\w*\.(\w+)$').firstMatch(e);
    if (member != null) {
      for (final s in sources) {
        final d = declOf(member.group(1)!).firstMatch(s.code);
        if (d != null) return resolve(d.group(1)!, s, depth + 1);
      }
      return null;
    }
    if (RegExp(r'^[a-z_]\w*$').hasMatch(e)) {
      final d = declOf(e).firstMatch(src.code);
      if (d != null) return resolve(d.group(1)!, src, depth + 1);
    }
    return null;
  }

  List<Brightness> brightnessOf(ScannedSource src, int open, int close) {
    final arg = namedArgument(src.structure, open, close, 'brightness');
    if (arg == null) return const [Brightness.light];
    final text = src.structure.substring(arg.start, arg.end).trim();
    if (text == 'Brightness.dark') return const [Brightness.dark];
    if (text == 'Brightness.light') return const [Brightness.light];
    return const [Brightness.light, Brightness.dark];
  }

  void add(ScannedSource src, int at, SourceRange expr, List<Brightness> bs,
      String how, {bool fromSeed = false}) {
    final text = src.code.substring(expr.start, expr.end).trim();
    final where = '${src.relative}:${lineOf(src.original, at)}';
    final v = resolve(text, src);
    if (v == null) {
      findings.add(ConformanceFinding(
        _check,
        "$where: cannot resolve the accent '$text' in $how to a colour — "
        'record what the app paints in FleetAppConfig.accentColors '
        '(every theme, every user-selectable preset)',
      ));
      return;
    }
    for (final b in bs) {
      final painted = fromSeed
          ? ColorScheme.fromSeed(seedColor: Color(v), brightness: b)
              .primary
              .toARGB32()
          : v;
      accents.add(_Accent(
          b,
          painted,
          fromSeed
              ? '$how seed ${_hex(v)} → rendered primary, $where'
              : '$how, $where'));
    }
  }

  for (final src in sources) {
    for (final (open, close) in src.calls('ColorScheme.fromSeed')) {
      final bs = brightnessOf(src, open, close);
      // A chained .copyWith(primary:) overrides the tone-mapped primary.
      final tail = RegExp(r'^\s*\.\s*copyWith\s*\(')
          .firstMatch(src.structure.substring(close + 1));
      if (tail != null) {
        final cOpen = close + tail.end;
        final cClose = matchingClose(src.structure, cOpen);
        final p = cClose == null
            ? null
            : namedArgument(src.structure, cOpen, cClose, 'primary');
        if (p != null) {
          add(src, open, p, bs, 'ColorScheme.fromSeed(...).copyWith(primary:)');
          continue;
        }
      }
      final primary = namedArgument(src.structure, open, close, 'primary');
      if (primary != null) {
        add(src, open, primary, bs, 'ColorScheme.fromSeed(primary:)');
        continue;
      }
      final seed = namedArgument(src.structure, open, close, 'seedColor');
      if (seed != null) {
        add(src, open, seed, bs, 'ColorScheme.fromSeed', fromSeed: true);
      }
    }
    for (final (ctor, fixed) in const [
      ('ColorScheme.light', Brightness.light),
      ('ColorScheme.dark', Brightness.dark),
      ('ColorScheme', null),
    ]) {
      for (final (open, close) in src.calls(ctor)) {
        // `ColorScheme` must not re-match `ColorScheme.light(`: calls()
        // needs `(` right after the name, so it cannot.
        final primary = namedArgument(src.structure, open, close, 'primary');
        if (primary == null) continue;
        add(src, open, primary,
            fixed == null ? brightnessOf(src, open, close) : [fixed], '$ctor(primary:)');
      }
    }
    for (final (builder, roleSet, b) in const [
      ('OhTheme.light', 'light', Brightness.light),
      ('OhTheme.hearthDark', 'hearthDark', Brightness.dark),
      ('OhTheme.night', 'night', Brightness.dark),
    ]) {
      for (final (open, close) in src.calls(builder)) {
        final accent = namedArgument(src.structure, open, close, 'appAccent');
        if (accent != null) {
          add(src, open, accent, [b], '$builder(appAccent:)');
          continue;
        }
        final warmth = roles[roleSet]?.warmth;
        final where = '${src.relative}:${lineOf(src.original, open)}';
        if (warmth == null) {
          findings.add(ConformanceFinding(
            _check,
            '$where: $builder() uses the $roleSet warmth role, which could '
            'not be read from color_roles.dart',
          ));
        } else {
          accents.add(_Accent(b, warmth,
              "$builder() default = ohStyle's OhColorRoles.$roleSet.warmth, $where"));
        }
      }
    }
  }
}
