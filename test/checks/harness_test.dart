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
  }

  test('conformant fixture yields no findings', () {
    writeConformant();
    expect(checkHarnessCanon(root: root), isEmpty);
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
