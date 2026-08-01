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

  final workflowsDir = Directory('${_ciRoot(root).path}/.github/workflows');
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

  // Generated sources belong to the build, not to git. CI and every local
  // build run build_runner, so a committed `.g.dart` is only a copy that
  // can drift from the source it was generated from — and it drifts
  // silently, because nothing re-checks it.
  //
  // Only apps that actually generate are asked: a rule about output that
  // is never produced is a rule about nothing, and those are how a
  // conformance suite loses the authority to be believed.
  final pubspecFile = File('${root.path}/pubspec.yaml');
  final generates = pubspecFile.existsSync() &&
      pubspecFile.readAsStringSync().contains('build_runner');
  if (generates) {
    final gitignore = File('${root.path}/.gitignore');
    if (!gitignore.existsSync()) {
      findings.add(const ConformanceFinding(
        check,
        '.gitignore not found — the fleet ignores generated sources '
        '(*.g.dart) rather than committing a copy that can go stale',
      ));
    } else if (!gitignore.readAsLinesSync().any((l) => l.trim() == '*.g.dart')) {
      findings.add(const ConformanceFinding(
        check,
        '.gitignore has no `*.g.dart` rule — CI and local builds both run '
        'build_runner, so a committed generated file is a second source of '
        'truth that nothing keeps honest; add the rule and '
        '`git rm --cached` what is already tracked',
      ));
    }

    // The rule existing is not the rule being in effect: .gitignore only
    // governs UNtracked paths, so adding it leaves every already-committed
    // file exactly where it was. Two apps sat in that state with the rule
    // in place and this check green, which made it a rule about a rule.
    findings.addAll(_trackedGeneratedSources(root));
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

/// The directory GitHub actually reads workflows from: the nearest ancestor
/// carrying `.git` (a directory, or the file a worktree checkout leaves).
/// A nested app root (the PrimingTrellis/app layout) must be judged by the
/// CI that runs, not asked to keep a decorative copy under itself. Roots
/// outside any repository — unit-test fixtures — stay their own CI root,
/// which is also every flat-layout app, judged exactly as before.
Directory _ciRoot(Directory root) {
  var dir = root.absolute;
  while (true) {
    if (FileSystemEntity.typeSync('${dir.path}/.git') !=
        FileSystemEntityType.notFound) {
      return dir;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) return root;
    dir = parent;
  }
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

/// Generated sources git is still tracking, whatever `.gitignore` says.
///
/// Shells out because only git knows its own index. When git is absent or
/// the directory is not a repo we report nothing — that is genuinely
/// unknowable here, and the `.gitignore` rule above still applies.
List<ConformanceFinding> _trackedGeneratedSources(Directory root) {
  final ProcessResult result;
  try {
    result = Process.runSync(
      'git',
      ['ls-files', '--', '*.g.dart'],
      workingDirectory: root.path,
    );
  } on ProcessException {
    return const [];
  }
  if (result.exitCode != 0) return const [];

  final tracked = (result.stdout as String)
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();
  if (tracked.isEmpty) return const [];

  return [
    ConformanceFinding(
      'C6-harness',
      '${tracked.length} generated file(s) are still tracked by git despite '
      'the .gitignore rule (${tracked.take(3).join(', ')}'
      '${tracked.length > 3 ? ', …' : ''}) — gitignore only governs '
      'UNtracked paths; run `git rm --cached` on them',
    ),
  ];
}
