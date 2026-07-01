import 'dart:io';

import '../canonical_templates.dart';
import '../findings.dart';

/// C6 — the shared test/CI harness, held to the canon.
///
/// Three structural constraints:
///  * `test/flutter_test_config.dart` must equal [canonicalFlutterTestConfig]
///    — a divergent config is why one app's goldens load real fonts while
///    another's render placeholder boxes (same widget, different PNG);
///  * `analysis_options.yaml` must equal [canonicalAnalysisOptions] unless
///    [analysisOptionsOverrideRecorded] — Reckon/PT/StillLife carry
///    deliberately-tighter configs, recorded per-app;
///  * CI workflows must exist, and every `flutter-version:` pin in them must
///    equal [requiredCiFlutterVersion] — a fictional pin (the 3.44.x still
///    live in PunctumTemporis CI) is a config-hallucination class that must
///    be structurally unshippable.
///
/// Content comparison normalizes CRLF→LF and strips trailing whitespace per
/// line on BOTH sides — nothing looser.
List<ConformanceFinding> checkHarnessCanon({
  required Directory root,
  bool analysisOptionsOverrideRecorded = false,
  String requiredCiFlutterVersion = '3.38.7',
}) {
  const check = 'C6-harness';
  final findings = <ConformanceFinding>[];

  final testConfig = File('${root.path}/test/flutter_test_config.dart');
  if (!testConfig.existsSync()) {
    findings.add(const ConformanceFinding(
      check,
      'test/flutter_test_config.dart not found — without the canonical '
      'config this app\'s goldens render placeholder boxes instead of real '
      'fonts; copy canonicalFlutterTestConfig from oh_fleet_conformance',
    ));
  } else {
    final line = _firstDivergingLine(
      testConfig.readAsStringSync(),
      canonicalFlutterTestConfig,
    );
    if (line != null) {
      findings.add(ConformanceFinding(
        check,
        'test/flutter_test_config.dart diverges from the canonical template '
        'at line $line — divergent configs make goldens render differently '
        'across apps; re-sync from canonicalFlutterTestConfig',
      ));
    }
  }

  final analysis = File('${root.path}/analysis_options.yaml');
  if (!analysis.existsSync()) {
    findings.add(const ConformanceFinding(
      check,
      'analysis_options.yaml not found — the app carries no lint config; '
      'copy canonicalAnalysisOptions from oh_fleet_conformance',
    ));
  } else if (!analysisOptionsOverrideRecorded) {
    final line = _firstDivergingLine(
      analysis.readAsStringSync(),
      canonicalAnalysisOptions,
    );
    if (line != null) {
      findings.add(ConformanceFinding(
        check,
        'analysis_options.yaml diverges from the stock template at line '
        '$line — either re-sync it or record the deliberate override in the '
        'app\'s FleetAppConfig (analysisOptionsOverrideRecorded)',
      ));
    }
  }

  final workflowsDir = Directory('${root.path}/.github/workflows');
  final workflows = (workflowsDir.existsSync()
          ? workflowsDir.listSync().whereType<File>().where(
              (f) => f.path.endsWith('.yml') || f.path.endsWith('.yaml'))
          : const Iterable<File>.empty())
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  if (workflows.isEmpty) {
    findings.add(const ConformanceFinding(
      check,
      'no *.yml/*.yaml under .github/workflows — the app has no CI '
      '(the Trellis/Mantle situation); nothing verifies that it builds',
    ));
  } else {
    for (final workflow in workflows) {
      final name = workflow.uri.pathSegments.last;
      // Comment content is ignored line by line: '# flutter-version: …'
      // notes are not pins, and a commented-out flutter-action step is not
      // a Flutter setup.
      final lines = workflow
          .readAsStringSync()
          .replaceAll('\r\n', '\n')
          .split('\n')
          .map(_stripYamlComment)
          .toList();
      var pinned = false;
      for (final line in lines) {
        final match = _flutterVersionPattern.firstMatch(line);
        if (match == null) continue;
        pinned = true;
        final value = _unquote(match.group(1)!.trim());
        if (value.startsWith(r'${{')) {
          findings.add(ConformanceFinding(
            check,
            '.github/workflows/$name pins flutter-version through a GitHub '
            'expression ($value) — an expression pin cannot be verified '
            'against the fleet pin $requiredCiFlutterVersion; write the '
            'literal version',
          ));
        } else if (value != requiredCiFlutterVersion) {
          findings.add(ConformanceFinding(
            check,
            '.github/workflows/$name pins flutter-version: $value but the '
            'fleet CI pin is $requiredCiFlutterVersion — unverified pins are '
            'how fictional Flutter versions ship',
          ));
        }
      }
      if (!pinned &&
          lines.any((l) => l.contains('subosito/flutter-action'))) {
        findings.add(ConformanceFinding(
          check,
          '.github/workflows/$name uses subosito/flutter-action with no '
          'flutter-version at all — an unpinned setup floats to whatever '
          'Flutter the action ships next; pin $requiredCiFlutterVersion',
        ));
      }
    }
  }

  return findings;
}

/// CRLF→LF + strip trailing whitespace per line: the ONLY normalization
/// applied before content comparison. Anything looser would hide real
/// divergence.
List<String> _normalizedLines(String content) => content
    .replaceAll('\r\n', '\n')
    .split('\n')
    .map((line) => line.trimRight())
    .toList();

/// 1-based first line where [actual] differs from [canonical] after
/// normalization (a missing/extra tail counts as differing at the first
/// absent line), or null if identical.
int? _firstDivergingLine(String actual, String canonical) {
  final a = _normalizedLines(actual);
  final c = _normalizedLines(canonical);
  final shared = a.length < c.length ? a.length : c.length;
  for (var i = 0; i < shared; i++) {
    if (a[i] != c[i]) return i + 1;
  }
  return a.length == c.length ? null : shared + 1;
}

// Matches `flutter-version:` but never `flutter-version-file:` (the literal
// must be followed by optional whitespace then a colon). Applied per
// comment-stripped line, capturing the rest of the line so an expression
// value (`${{ env.X }}`) survives whole.
final _flutterVersionPattern = RegExp(r'flutter-version\s*:\s*(.+)$');

/// The line up to its YAML comment: '#' starts a comment at line start or
/// after whitespace (a '#' inside a value does not).
String _stripYamlComment(String line) {
  for (var i = 0; i < line.length; i++) {
    if (line[i] == '#' &&
        (i == 0 || line[i - 1] == ' ' || line[i - 1] == '\t')) {
      return line.substring(0, i);
    }
  }
  return line;
}

/// YAML quoting is not drift: '3.38.7', "3.38.7", and bare 3.38.7 are the
/// same pin.
String _unquote(String value) {
  if (value.length >= 2 &&
      ((value.startsWith("'") && value.endsWith("'")) ||
          (value.startsWith('"') && value.endsWith('"')))) {
    return value.substring(1, value.length - 1);
  }
  return value;
}
