import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oh_fleet_conformance/src/canonical_templates.dart';
import 'package:oh_fleet_conformance/src/checks/harness.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('ohfc_harness_');
  });

  tearDown(() {
    root.deleteSync(recursive: true);
  });

  void write(String relative, String content) {
    final file = File('${root.path}/$relative');
    file.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  String workflowPinned(String version) => '''
name: CI
on: [push]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: $version
      - run: flutter test
''';

  /// The fixture every violation test starts from, then breaks one thing.
  void writeConformant() {
    write('test/flutter_test_config.dart', canonicalFlutterTestConfig);
    write('analysis_options.yaml', canonicalAnalysisOptions);
    write('.github/workflows/ci.yml', workflowPinned("'3.38.7'"));
    write('.gitignore', 'build/\n*.g.dart\n');
  }

  test('conformant fixture yields no findings', () {
    writeConformant();
    expect(checkHarnessCanon(root: root), isEmpty);
  });

  group('generated sources stay generated', () {
    // CI and every local build run build_runner, so a committed .g.dart is
    // only a copy that can drift from its source. Three apps had drifted
    // this way (StillLife 14 files, Lullaby 8, Reckon 1) while the rest of
    // the fleet ignored them — the same silent divergence C7 was hoisted
    // to stop, one directory over.
    test('an app that ignores *.g.dart is conformant', () {
      writeConformant();
      write('.gitignore', 'build/\n*.g.dart\n');
      expect(checkHarnessCanon(root: root), isEmpty);
    });

    test('a .gitignore with no *.g.dart rule is a finding', () {
      writeConformant();
      write('pubspec.yaml', 'name: fixture\ndev_dependencies:\n  build_runner: ^2.4.15\n');
      write('.gitignore', 'build/\n.dart_tool/\n');
      final findings = checkHarnessCanon(root: root);
      expect(findings, isNotEmpty);
      expect(findings.map((f) => f.message).join(), contains('*.g.dart'));
    });

    test('an app with no codegen is not asked to ignore codegen', () {
      // Trellis and PunctumTemporis have no build_runner at all. Demanding
      // the rule there would be a rule about nothing, and rules about
      // nothing are how a conformance suite loses its authority.
      writeConformant();
      write('.gitignore', 'build/\n');
      write('pubspec.yaml', 'name: fixture\ndev_dependencies:\n  flutter_lints: ^6.0.0\n');
      expect(checkHarnessCanon(root: root), isEmpty);
    });

    test('an app that DOES run build_runner must ignore its output', () {
      writeConformant();
      write('.gitignore', 'build/\n');
      write('pubspec.yaml', 'name: fixture\ndev_dependencies:\n  build_runner: ^2.4.15\n');
      final findings = checkHarnessCanon(root: root);
      expect(findings, isNotEmpty);
      expect(findings.map((f) => f.message).join(), contains('*.g.dart'));
    });

    test('the rule existing is not the same as the rule being in effect',
        () {
      // Lilt and Mantle had the .gitignore rule AND still tracked their
      // generated files: gitignore only governs UNtracked paths, so adding
      // it changed nothing that was already committed. C6 passed them both,
      // which made this check a rule about a rule.
      writeConformant();
      write('pubspec.yaml',
          'name: fixture\ndev_dependencies:\n  build_runner: ^2.4.15\n');
      write('.gitignore', 'build/\n*.g.dart\n');
      write('lib/model.g.dart', '// generated');

      final git = ['init', '-q', '-b', 'main'];
      Process.runSync('git', git, workingDirectory: root.path);
      // -f because the file is ignored; that is precisely how it happens.
      Process.runSync('git', ['add', '-f', 'lib/model.g.dart'],
          workingDirectory: root.path);

      final findings = checkHarnessCanon(root: root);
      expect(findings, isNotEmpty);
      expect(findings.map((f) => f.message).join(), contains('tracked'));
    });

    test('a missing .gitignore is a finding, not a free pass', () {
      writeConformant();
      write('pubspec.yaml', 'name: fixture\ndev_dependencies:\n  build_runner: ^2.4.15\n');
      File('${root.path}/.gitignore').deleteSync();
      final findings = checkHarnessCanon(root: root);
      expect(findings, isNotEmpty);
      expect(findings.map((f) => f.message).join(), contains('.gitignore'));
    });
  });

  test('the embedded test config really is the FontManifest-aware variant',
      () {
    // Guards against embedding the wrong file: only the canonical variant
    // loads the app's own bundled fonts via FontManifest.json.
    expect(canonicalFlutterTestConfig, contains('FontManifest.json'));
  });

  test('the template guards each font family individually', () {
    // One family's failure must log and continue, not abort the families
    // after it: MaterialIcons loads first, so a single catch-all around the
    // loop would let its failure silently kill Lora/Nunito. The family loop
    // must therefore carry its own try INSIDE the loop body.
    final body = canonicalFlutterTestConfig.substring(
      canonicalFlutterTestConfig.indexOf('_loadAppBundledFonts() async'),
      canonicalFlutterTestConfig.indexOf('_loadSdkFonts() async'),
    );
    final loopRegion =
        body.substring(body.indexOf('for (final dynamic entry in families)'));
    expect(loopRegion, contains('try {'));
    expect(loopRegion, contains('await loader.load();'));
    // And the guard swallowing a family's failure must not be silent.
    expect(loopRegion, contains('catch'));
    expect(loopRegion, contains('print('));
  });

  test('missing test/flutter_test_config.dart is a finding', () {
    writeConformant();
    File('${root.path}/test/flutter_test_config.dart').deleteSync();
    final findings = checkHarnessCanon(root: root);
    expect(findings, hasLength(1));
    expect(findings.single.check, 'C6-harness');
    expect(findings.single.message, contains('flutter_test_config.dart'));
  });

  test('divergent flutter_test_config names the first differing line', () {
    writeConformant();
    // Keep lines 1-2 canonical, replace line 3, truncate the rest.
    final divergent =
        '${canonicalFlutterTestConfig.split('\n').take(2).join('\n')}\n'
        '// divergent line\n';
    write('test/flutter_test_config.dart', divergent);
    final findings = checkHarnessCanon(root: root);
    expect(findings, hasLength(1));
    expect(findings.single.message, contains('flutter_test_config.dart'));
    expect(findings.single.message, contains('line 3'));
  });

  test('CRLF line endings and trailing whitespace still conform', () {
    // Normalization proof: editor/OS noise is not divergence.
    writeConformant();
    write(
      'test/flutter_test_config.dart',
      canonicalFlutterTestConfig.replaceAll('\n', '\r\n'),
    );
    write(
      'analysis_options.yaml',
      canonicalAnalysisOptions.split('\n').map((l) => '$l  ').join('\n'),
    );
    expect(checkHarnessCanon(root: root), isEmpty);
  });

  test('missing analysis_options.yaml is a finding', () {
    writeConformant();
    File('${root.path}/analysis_options.yaml').deleteSync();
    final findings = checkHarnessCanon(root: root);
    expect(findings, hasLength(1));
    expect(findings.single.message, contains('analysis_options.yaml'));
  });

  test('divergent analysis_options fails unless the override is recorded', () {
    // The Reckon/PT/StillLife case: deliberately tighter lints, recorded
    // per-app — silent drift still fails.
    writeConformant();
    write(
      'analysis_options.yaml',
      'include: package:flutter_lints/flutter.yaml\n'
      'linter:\n'
      '  rules:\n'
      '    - always_use_package_imports\n',
    );
    final findings = checkHarnessCanon(root: root);
    expect(findings, hasLength(1));
    expect(findings.single.message, contains('analysis_options.yaml'));
    expect(
      checkHarnessCanon(root: root, analysisOptionsOverrideRecorded: true),
      isEmpty,
    );
  });

  test('no workflow files means the app has no CI — a finding', () {
    // The Trellis/Mantle situation: everything else conformant, zero CI.
    writeConformant();
    Directory('${root.path}/.github').deleteSync(recursive: true);
    final findings = checkHarnessCanon(root: root);
    expect(findings, hasLength(1));
    expect(findings.single.message, contains('CI'));
  });

  test('a fictional flutter-version pin fails, naming file and value', () {
    // The config-hallucination class: 3.44.x does not exist, yet shipped.
    writeConformant();
    write('.github/workflows/ci.yml', workflowPinned("'3.44.x'"));
    final findings = checkHarnessCanon(root: root);
    expect(findings, hasLength(1));
    expect(findings.single.message, contains('ci.yml'));
    expect(findings.single.message, contains('3.44.x'));
  });

  test('matching pins conform whatever the quoting style', () {
    writeConformant();
    write('.github/workflows/ci.yml', workflowPinned("'3.38.7'"));
    write('.github/workflows/deploy.yaml', workflowPinned('"3.38.7"'));
    write('.github/workflows/nightly.yml', workflowPinned('3.38.7'));
    expect(checkHarnessCanon(root: root), isEmpty);
  });

  test('one bad pin among several workflows is exactly one finding', () {
    writeConformant();
    write('.github/workflows/deploy.yaml', workflowPinned("'3.44.x'"));
    final findings = checkHarnessCanon(root: root);
    expect(findings, hasLength(1));
    expect(findings.single.message, contains('deploy.yaml'));
    expect(findings.single.message, contains('3.44.x'));
  });

  test('a flutter-version inside a YAML comment is not a pin', () {
    writeConformant();
    write(
      '.github/workflows/ci.yml',
      '# flutter-version: 3.44.x — an old note, not a pin\n'
      '${workflowPinned("'3.38.7'")}',
    );
    expect(checkHarnessCanon(root: root), isEmpty);
  });

  test('an expression pin is its own finding, not a literal mismatch', () {
    writeConformant();
    write(
      '.github/workflows/ci.yml',
      workflowPinned(r'${{ env.FLUTTER_VERSION }}'),
    );
    final findings = checkHarnessCanon(root: root);
    expect(findings, hasLength(1));
    expect(findings.single.message, contains('ci.yml'));
    expect(findings.single.message, contains('expression'));
    expect(findings.single.message, contains('env.FLUTTER_VERSION'));
  });

  test('flutter-action with no flutter-version at all is a finding', () {
    // The silent-pass hole: a workflow that sets up Flutter but never pins
    // it floats to whatever the action ships next.
    writeConformant();
    write('.github/workflows/ci.yml', '''
name: CI
on: [push]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
      - run: flutter test
''');
    final findings = checkHarnessCanon(root: root);
    expect(findings, hasLength(1));
    expect(findings.single.message, contains('ci.yml'));
    expect(findings.single.message, contains('no flutter-version'));
  });

  test('a workflow without flutter-action needs no pin', () {
    writeConformant();
    write('.github/workflows/pages.yml', '''
name: Pages
on: [push]
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
''');
    expect(checkHarnessCanon(root: root), isEmpty);
  });

  test('a commented-out flutter-action does not demand a pin', () {
    writeConformant();
    write('.github/workflows/pages.yml', '''
name: Pages
on: [push]
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      # - uses: subosito/flutter-action@v2
''');
    expect(checkHarnessCanon(root: root), isEmpty);
  });
}
