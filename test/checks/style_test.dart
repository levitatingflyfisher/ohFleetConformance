import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oh_fleet_conformance/src/checks/style.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('ohfc_style_');
  });

  tearDown(() {
    root.deleteSync(recursive: true);
  });

  File writeFile(String relativePath, String content) {
    final file = File('${root.path}/$relativePath');
    file.createSync(recursive: true);
    file.writeAsStringSync(content);
    return file;
  }

  String pubspecWith(String designDepBlock) => '''
name: fixture_app
dependencies:
  flutter:
    sdk: flutter
$designDepBlock''';

  const canonicalDep = '''
  openhearth_design:
    path: ../../ohStyle/openhearth_design
''';
  const vendoredDep = '''
  openhearth_design:
    path: packages/openhearth_design
''';

  // Real canonical token values (hearth500 is the one Reckon's fork diverged
  // from; sage500 is the one Sundial legitimately shares).
  const hearth500 = 0xFFA85040;
  const sage500 = 0xFF5E9478;

  // --- checkCanonicalDesignPackage ------------------------------------

  test('clean fixture yields no findings from either check', () {
    writeFile('pubspec.yaml', pubspecWith(canonicalDep));
    writeFile('lib/main.dart', 'const own = Color(0xFF336699);\n');
    expect(checkCanonicalDesignPackage(root: root), isEmpty);
    expect(
      checkNoRetypedTokenLiterals(
        root: root,
        canonicalTokenValues: {hearth500, sage500},
      ),
      isEmpty,
    );
  });

  test('missing openhearth_design dependency is a finding', () {
    writeFile('pubspec.yaml', pubspecWith(''));
    final findings = checkCanonicalDesignPackage(root: root);
    expect(findings, hasLength(1));
    expect(findings.single.check, 'C1-style');
    expect(findings.single.message, contains('openhearth_design'));
  });

  test('a hosted (non-path) dependency is a finding', () {
    writeFile('pubspec.yaml', pubspecWith('  openhearth_design: ^1.0.0\n'));
    final findings = checkCanonicalDesignPackage(root: root);
    expect(findings, hasLength(1));
    expect(findings.single.message, contains('path dependency'));
  });

  test('a vendored-fork path in pubspec is a finding naming the fork', () {
    // The Reckon scenario: a repo-local "reconstruction" of the package.
    writeFile('pubspec.yaml', pubspecWith(vendoredDep));
    final findings = checkCanonicalDesignPackage(root: root);
    expect(findings, hasLength(1));
    expect(findings.single.message, contains('vendored fork'));
    expect(findings.single.message, contains('packages/openhearth_design'));
  });

  test('a fork directory on disk fails even when pubspec is clean', () {
    writeFile('pubspec.yaml', pubspecWith(canonicalDep));
    writeFile(
      'packages/openhearth_design/pubspec.yaml',
      'name: openhearth_design\n',
    );
    final findings = checkCanonicalDesignPackage(root: root);
    expect(findings, hasLength(1));
    expect(findings.single.message, contains('packages/openhearth_design'));
  });

  test('missing pubspec.yaml is itself a finding', () {
    final findings = checkCanonicalDesignPackage(root: root);
    expect(findings, hasLength(1));
    expect(findings.single.message, contains('pubspec.yaml'));
  });

  test('a commented path line in the block is skipped, not taken', () {
    // The real path below the comment is canonical; the '# path:' comment
    // must not be read as the dependency's path.
    writeFile('pubspec.yaml', pubspecWith('''
  openhearth_design:
    # path: packages/openhearth_design
    path: ../../ohStyle/openhearth_design
'''));
    expect(checkCanonicalDesignPackage(root: root), isEmpty);
  });

  test('a block whose only path line is a comment has no path', () {
    writeFile('pubspec.yaml', pubspecWith('''
  openhearth_design:
    # path: ../../ohStyle/openhearth_design
'''));
    final findings = checkCanonicalDesignPackage(root: root);
    expect(findings, hasLength(1));
    expect(findings.single.message, contains('path dependency'));
  });

  test('a fork dir merely embedding the canonical fragment fails', () {
    // contains() was satisfiable by any path that EMBEDS the fragment; the
    // path must END at the canonical package, not pass through it.
    writeFile('pubspec.yaml', pubspecWith('''
  openhearth_design:
    path: ../evil/ohStyle/openhearth_design-fork
'''));
    final findings = checkCanonicalDesignPackage(root: root);
    expect(findings, hasLength(1));
    expect(findings.single.message, contains('vendored fork'));
    expect(
      findings.single.message,
      contains('../evil/ohStyle/openhearth_design-fork'),
    );
  });

  test('a nested copy under the canonical-looking suffix fails', () {
    writeFile('pubspec.yaml', pubspecWith('''
  openhearth_design:
    path: vendor/ohStyle/openhearth_design/fork
'''));
    expect(checkCanonicalDesignPackage(root: root), hasLength(1));
  });

  test('a parent dir merely ending in ohStyle is not canonical', () {
    // 'notohStyle/openhearth_design' string-ends-with the fragment; the
    // segment boundary must be respected.
    writeFile('pubspec.yaml', pubspecWith('''
  openhearth_design:
    path: ../notohStyle/openhearth_design
'''));
    expect(checkCanonicalDesignPackage(root: root), hasLength(1));
  });

  test('a trailing slash on the canonical path still conforms', () {
    writeFile('pubspec.yaml', pubspecWith('''
  openhearth_design:
    path: ../../ohStyle/openhearth_design/
'''));
    expect(checkCanonicalDesignPackage(root: root), isEmpty);
  });

  test('a fork in dependency_overrides fails even with a clean dependency',
      () {
    // firstMatch-only parsing examined the dependencies entry and never the
    // override — the override is what pub actually resolves.
    writeFile('pubspec.yaml', '''
name: fixture_app
dependencies:
  flutter:
    sdk: flutter
$canonicalDep
dependency_overrides:
  openhearth_design:
    path: packages/openhearth_design
''');
    final findings = checkCanonicalDesignPackage(root: root);
    expect(findings, hasLength(1));
    expect(findings.single.message, contains('vendored fork'));
    expect(findings.single.message, contains('packages/openhearth_design'));
  });

  // --- canonicalTokenValuesFrom ---------------------------------------

  test('canonicalTokenValuesFrom extracts every Color hex literal', () {
    writeFile('design/lib/src/colors.dart', '''
import 'package:flutter/material.dart';

abstract final class OhColors {
  static const hearth500 = Color(0xFFA85040);
  static const sage500 = Color(0xFF5E9478);
  static const ink900 = Color(0xff2d2a26); // lower-case hex must parse too
}
''');
    expect(
      canonicalTokenValuesFrom(Directory('${root.path}/design')),
      {hearth500, sage500, 0xFF2D2A26},
    );
  });

  test('canonicalTokenValuesFrom throws when colors.dart is missing', () {
    // Fail loud: an empty token set would make the retyped-literal check
    // pass vacuously against every app.
    expect(
      () => canonicalTokenValuesFrom(Directory('${root.path}/design')),
      throwsStateError,
    );
  });

  // --- checkNoRetypedTokenLiterals ------------------------------------

  test('a retyped canonical literal is cited with file, line, and hex', () {
    writeFile('lib/theme.dart', '''
import 'package:flutter/material.dart';

const warmAccent = Color(0xFFA85040);
''');
    final findings = checkNoRetypedTokenLiterals(
      root: root,
      canonicalTokenValues: {hearth500, sage500},
    );
    expect(findings, hasLength(1));
    expect(findings.single.check, 'C1-style');
    expect(findings.single.message, contains('lib/theme.dart:3'));
    expect(findings.single.message, contains('0xFFA85040'));
    expect(findings.single.message, contains('openhearth_design'));
  });

  test('the allowed set suppresses a recorded deliberate coincidence', () {
    // Sundial's signature sage IS OhColors.sage500 — a legitimate exception
    // the app records in its FleetAppConfig.
    writeFile('lib/theme.dart', 'const sage = Color(0xFF5E9478);\n');
    expect(
      checkNoRetypedTokenLiterals(
        root: root,
        canonicalTokenValues: {hearth500, sage500},
        allowed: {sage500},
      ),
      isEmpty,
    );
  });

  test('generated .g.dart and .freezed.dart files are skipped', () {
    writeFile('lib/gen/theme.g.dart', 'const c = Color(0xFFA85040);\n');
    writeFile('lib/model.freezed.dart', 'const c = Color(0xFF5E9478);\n');
    expect(
      checkNoRetypedTokenLiterals(
        root: root,
        canonicalTokenValues: {hearth500, sage500},
      ),
      isEmpty,
    );
  });

  test('a hex literal outside the canonical set is not flagged', () {
    // App-own colors are the app's business; only token collisions matter.
    writeFile('lib/theme.dart', 'const own = Color(0xFF123456);\n');
    expect(
      checkNoRetypedTokenLiterals(
        root: root,
        canonicalTokenValues: {hearth500, sage500},
      ),
      isEmpty,
    );
  });
}
