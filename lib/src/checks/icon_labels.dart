import 'dart:io';

import '../findings.dart';
import '../source_scan.dart';

const _check = 'C11-iconLabels';
const _strictCheck = 'C11-strictBarLabels';

/// `PopupMenuButton(` with or without type arguments.
final _popupMenu =
    RegExp(r'(?<![A-Za-z0-9_])PopupMenuButton\s*(?:<[^()]*?>)?\s*\(');
final _visibleText = RegExp(r'(?<![A-Za-z0-9_])Text\s*\(');
final _keyLiteral = RegExp(r"""Key\s*\(\s*['"]([^'"]+)['"]\s*\)""");

/// The icon-only constructors C11 looks for inside `actions:`. Word-bounded
/// matching keeps `IconButton(` from matching `OhIconButton(` and
/// `IconButton.filled(` from matching `IconButton(`.
const _iconOnly = [
  'IconButton',
  'IconButton.filled',
  'IconButton.filledTonal',
  'IconButton.outlined',
  'OhIconButton.filled',
  'OhIconButton.filledTonal',
];

/// C11 — an app-bar action says what it does.
///
/// A glyph alone in the top bar makes people guess (Sundial's History view
/// switch kept its only word in a tooltip, which a phone never hovers).
/// The operator's ruling (roadmap Phase 6, item 45): **icon plus a short
/// label; rare actions in a worded menu.**
///
/// **The rule, kept static and conservative.** Inside the `actions:` list
/// of every `AppBar(`/`SliverAppBar(` under `lib/`, each icon-only button
/// (`IconButton`, its `.filled`/`.filledTonal`/`.outlined` variants,
/// `OhIconButton.filled`/`.filledTonal`) needs a `tooltip:` or a visible
/// `Text(` inside its `icon:`. A tooltip is the floor this check enforces,
/// not the target: the message recommends `TextButton.icon(icon:, label:)`.
/// Labelled buttons and `PopupMenuButton` (the worded menu) are compliant
/// by not being icon-only.
///
/// **False negatives, recorded honestly.** Actions built elsewhere
/// (`actions: _buildActions()`, a list variable, a custom action widget
/// wrapping `IconButton` in another file) are not seen; `leading:` and
/// bottom bars are out of scope; a tooltip passes although it is invisible
/// on touch. **False positives:** an icon whose meaning is universal (a
/// close ×) still needs a tooltip — cheap, and it names the action for
/// screen readers.
///
/// **Strict mode** (`strict: true`, the opt-in `FleetCheck.c11StrictBarLabels`)
/// holds the ruling itself rather than the floor: a tooltip no longer
/// passes. Every icon-only button in `actions:` is a finding unless its
/// `icon:` shows a `Text`, and so is a `PopupMenuButton` whose face is its
/// default icon (no `child:` showing a `Text`). The fix it names is
/// openhearth_design's `OhBarAction` (icon plus a short label that folds
/// into the tooltip only above 1.5x text) and `OhBarOverflow` (the worded
/// More menu). Labelled buttons (`OhBarAction`, `TextButton.icon`) pass by
/// not being icon-only. Same static reach and false negatives as above.
///
/// **Strict exemptions** (`exemptions`, from `FleetAppConfig
/// .barLabelExemptions`): a keyed control whose word the static scan cannot
/// see (a face built by a widget defined elsewhere) is exempted as
/// `'lib/path.dart#<Key string>'` with its reason. An empty reason, and an
/// exemption that matches no finding, are findings.
///
/// Cannot pass by finding nothing: no Dart sources, or no
/// `AppBar`/`SliverAppBar` parsed anywhere, is a finding.
List<ConformanceFinding> checkAppBarIconLabels({
  required Directory root,
  bool strict = false,
  Map<String, String> exemptions = const {},
}) {
  final check = strict ? _strictCheck : _check;
  final sources = ScannedSource.under(root);
  if (sources.isEmpty) {
    return [
      ConformanceFinding(
        check,
        'no Dart sources found under lib/ — nothing was swept, which is not '
        'the same as nothing being wrong',
      ),
    ];
  }

  final findings = <ConformanceFinding>[];
  final used = <String>{};
  bool exempt(ScannedSource src, int open, int close) {
    if (exemptions.isEmpty) return false;
    final key = namedArgument(src.structure, open, close, 'key');
    if (key == null) return false;
    final m = _keyLiteral.firstMatch(src.original.substring(key.start, key.end));
    if (m == null) return false;
    final id = '${src.relative}#${m.group(1)}';
    if (!exemptions.containsKey(id)) return false;
    used.add(id);
    return true;
  }

  var appBars = 0;
  for (final src in sources) {
    for (final bar in const ['AppBar', 'SliverAppBar']) {
      for (final (open, close) in src.calls(bar)) {
        appBars++;
        final actions = namedArgument(src.structure, open, close, 'actions');
        if (actions == null) continue;
        for (final ctor in _iconOnly) {
          for (final (bOpen, bClose) in src.calls(ctor)) {
            if (bOpen < actions.start || bClose > actions.end) continue;
            if (!strict &&
                namedArgument(src.structure, bOpen, bClose, 'tooltip') !=
                    null) {
              continue;
            }
            final icon = namedArgument(src.structure, bOpen, bClose, 'icon');
            if (icon != null &&
                _visibleText.hasMatch(
                    src.structure.substring(icon.start, icon.end))) {
              continue;
            }
            if (strict) {
              if (exempt(src, bOpen, bClose)) continue;
              findings.add(ConformanceFinding(
                _strictCheck,
                '${src.relative}:${lineOf(src.original, bOpen)} has an '
                'icon-only $ctor in $bar actions (a tooltip is not a visible '
                'name) — use '
                'OhBarAction(icon:, label:, onPressed:) so the word is on '
                'screen, or move a rare action into OhBarOverflow',
              ));
              continue;
            }
            findings.add(ConformanceFinding(
              _check,
              '${src.relative}:${lineOf(src.original, bOpen)} has an '
              'unlabelled $ctor in $bar actions — give it an icon plus a '
              'short visible label (TextButton.icon(icon:, label:)), move a '
              'rare action into a worded PopupMenuButton, or at the very '
              'least a tooltip:',
            ));
          }
        }
        if (!strict) continue;
        for (final m in _popupMenu.allMatches(src.structure)) {
          final pOpen = m.end - 1;
          final pClose = matchingClose(src.structure, pOpen);
          if (pClose == null) continue;
          if (pOpen < actions.start || pClose > actions.end) continue;
          final child =
              namedArgument(src.structure, pOpen, pClose, 'child');
          if (child != null &&
              _visibleText.hasMatch(
                  src.structure.substring(child.start, child.end))) {
            continue;
          }
          if (exempt(src, pOpen, pClose)) continue;
          findings.add(ConformanceFinding(
            _strictCheck,
            '${src.relative}:${lineOf(src.original, m.start)} has an '
            'icon-only PopupMenuButton in $bar actions — use OhBarOverflow '
            '(the worded More menu) or give it a child: that shows a Text',
          ));
        }
      }
    }
  }

  if (strict) {
    exemptions.forEach((id, reason) {
      if (reason.trim().isEmpty) {
        findings.add(ConformanceFinding(_strictCheck,
            'bar-label exemption $id has no reason — say why the word is '
            'on screen although the scan cannot see it'));
      } else if (!used.contains(id)) {
        findings.add(ConformanceFinding(_strictCheck,
            'bar-label exemption $id matches no finding — the control is '
            'gone or now passes; remove the exemption'));
      }
    });
  }

  if (appBars == 0) {
    return [
      ConformanceFinding(
        check,
        'no AppBar or SliverAppBar found under lib/ — nothing was swept, '
        'which is not the same as nothing being wrong',
      ),
    ];
  }
  return findings;
}
