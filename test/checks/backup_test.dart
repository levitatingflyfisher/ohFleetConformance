import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oh_fleet_conformance/src/checks/backup.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('ohfc_backup_');
  });

  tearDown(() {
    root.deleteSync(recursive: true);
  });

  void writeFile(String relative, String content) {
    final file = File('${root.path}/$relative');
    file.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  String pubspecWithDep({bool withSanctuaryBackupUi = true}) => '''
name: fixture_app
environment:
  sdk: ^3.4.0
dependencies:
  flutter:
    sdk: flutter
${withSanctuaryBackupUi ? '  sanctuary_backup_ui:\n    path: ../../packages/sanctuaryBackupUi\n' : ''}''';

  // Neighbouring blocks deliberately carry other versions so a parser that
  // grabs the wrong block (or the first `version:` line in the file) fails
  // these tests.
  String lockWithVersion(String version) => '''
packages:
  drift:
    dependency: "direct main"
    description:
      name: drift
      url: "https://pub.dev"
    source: hosted
    version: "2.20.3"
  sanctuary_backup_ui:
    dependency: "direct main"
    description:
      path: "../sanctuaryBackupUi"
      relative: true
    source: path
    version: "$version"
  yaml:
    dependency: transitive
    description:
      name: yaml
      url: "https://pub.dev"
    source: hosted
    version: "3.1.2"
sdks:
  dart: ">=3.4.0 <4.0.0"
''';

  void writeSerializer({
    bool previewable = true,
    bool usesEnvelope = true,
  }) {
    final iface =
        previewable ? 'PreviewableBackupSerializer' : 'BackupSerializer';
    final body = usesEnvelope
        ? "String serialize() => BackupEnvelope.wrap('{}');"
        : "String serialize() => '{\"v\":1}'; // hand-rolled";
    writeFile('lib/data/backup/serializer.dart', '''
import 'package:sanctuary_backup_ui/sanctuary_backup_ui.dart';

class FixtureSerializer implements $iface {
  $body
}
''');
  }

  void writeBackupConfig({bool withConfirmCopy = true}) {
    final copy = withConfirmCopy
        ? "  confirmTitle: 'Merge backup into this device?',\n"
            "  confirmActionLabel: 'Merge',\n"
        : '';
    writeFile('lib/backup_config.dart', '''
final backupConfig = BackupConfig(
  serializer: FixtureSerializer(),
$copy);
''');
  }

  void writeStartupMaintenance() {
    writeFile('lib/main.dart', '''
void main() {
  // post-first-frame
  runStartupMaintenance();
}
''');
  }

  /// The shape every adopted app should have; individual tests break one
  /// piece at a time.
  void writeConformantFixture({String lockVersion = '0.2.0'}) {
    writeFile('pubspec.yaml', pubspecWithDep());
    writeFile('pubspec.lock', lockWithVersion(lockVersion));
    writeSerializer();
    writeBackupConfig();
    writeStartupMaintenance();
  }

  test('fully conformant app yields no findings', () {
    writeConformantFixture();
    final findings = checkBackupConformance(
      root: root,
      mergeSemanticsRestore: true,
    );
    expect(findings, isEmpty);
  });

  test('pubspec without the sanctuary_backup_ui dependency is a finding', () {
    writeConformantFixture();
    writeFile('pubspec.yaml', pubspecWithDep(withSanctuaryBackupUi: false));
    // Keep the lock conformant so only the dependency finding fires.
    final findings = checkBackupConformance(
      root: root,
      mergeSemanticsRestore: true,
    );
    expect(findings, hasLength(1));
    expect(findings.single.message, contains('sanctuary_backup_ui'));
    expect(findings.single.message, contains('pubspec.yaml'));
  });

  test('a lock still pinned at 0.1.0 is a finding', () {
    // The never-relocked-after-the-retention-release scenario.
    writeConformantFixture(lockVersion: '0.1.0');
    final findings = checkBackupConformance(
      root: root,
      mergeSemanticsRestore: true,
    );
    expect(findings, hasLength(1));
    expect(findings.single.message, contains('0.1.0'));
    expect(findings.single.message, contains('0.2.0'));
  });

  test('a lock at 0.10.0 passes — the compare is numeric, not lexical', () {
    // Lexically "0.10.0" < "0.2.0"; numerically 10 >= 2.
    writeConformantFixture(lockVersion: '0.10.0');
    expect(
      checkBackupConformance(root: root, mergeSemanticsRestore: true),
      isEmpty,
    );
  });

  test('a missing lock file is not a finding (fresh checkout)', () {
    writeConformantFixture();
    File('${root.path}/pubspec.lock').deleteSync();
    expect(
      checkBackupConformance(root: root, mergeSemanticsRestore: true),
      isEmpty,
    );
  });

  test('no serializer implementing BackupSerializer is a finding', () {
    writeConformantFixture();
    File('${root.path}/lib/data/backup/serializer.dart').deleteSync();
    final findings = checkBackupConformance(
      root: root,
      mergeSemanticsRestore: true,
    );
    expect(findings, hasLength(1));
    expect(findings.single.message, contains('BackupSerializer'));
  });

  test('a serializer that never touches BackupEnvelope is a finding', () {
    // A hand-rolled envelope — exactly the divergence the shared package
    // exists to end.
    writeConformantFixture();
    writeSerializer(usesEnvelope: false);
    final findings = checkBackupConformance(
      root: root,
      mergeSemanticsRestore: true,
    );
    expect(findings, hasLength(1));
    expect(findings.single.message, contains('BackupEnvelope'));
  });

  test('a serializer without preview capability is a finding', () {
    writeConformantFixture();
    writeSerializer(previewable: false);
    final findings = checkBackupConformance(
      root: root,
      mergeSemanticsRestore: true,
    );
    expect(findings, hasLength(1));
    expect(findings.single.message, contains('PreviewableBackupSerializer'));
  });

  test('a merge-restore app without the confirm-copy overrides fails', () {
    // The StillLife scenario: the shared dialog says "Replace all data?"
    // while the restore actually merges.
    writeConformantFixture();
    writeBackupConfig(withConfirmCopy: false);
    final findings = checkBackupConformance(
      root: root,
      mergeSemanticsRestore: true,
    );
    expect(findings, hasLength(2));
    expect(
      findings.map((f) => f.message).join('\n'),
      allOf(contains('confirmTitle'), contains('confirmActionLabel')),
    );
  });

  test('a replace-restore app is not required to override the copy', () {
    writeConformantFixture();
    writeBackupConfig(withConfirmCopy: false);
    expect(
      checkBackupConformance(root: root, mergeSemanticsRestore: false),
      isEmpty,
    );
  });

  test('missing runStartupMaintenance is a finding', () {
    writeConformantFixture();
    writeFile('lib/main.dart', 'void main() {}\n');
    final findings = checkBackupConformance(
      root: root,
      mergeSemanticsRestore: true,
    );
    expect(findings, hasLength(1));
    expect(findings.single.message, contains('runStartupMaintenance'));
  });

  test('expectStartupMaintenance: false suppresses that sub-check', () {
    // PunctumTemporis drives the vault from its own service in its own
    // idiom.
    writeConformantFixture();
    writeFile('lib/main.dart', 'void main() {}\n');
    expect(
      checkBackupConformance(
        root: root,
        mergeSemanticsRestore: true,
        expectStartupMaintenance: false,
      ),
      isEmpty,
    );
  });

  // --- comments and strings are not conformance ------------------------

  test('BackupEnvelope only in a comment is still a finding', () {
    writeConformantFixture();
    writeFile('lib/data/backup/serializer.dart', '''
class FixtureSerializer implements PreviewableBackupSerializer {
  // BackupEnvelope.unwrap(...) — a comment is not an envelope
  String serialize() => '{"v":1}';
}
''');
    final findings = checkBackupConformance(
      root: root,
      mergeSemanticsRestore: true,
    );
    expect(findings, hasLength(1));
    expect(findings.single.message, contains('BackupEnvelope'));
  });

  test('runStartupMaintenance only in a comment is a finding', () {
    writeConformantFixture();
    writeFile('lib/main.dart', 'void main() {\n'
        '  // runStartupMaintenance(); — commented out is not called\n'
        '}\n');
    final findings = checkBackupConformance(
      root: root,
      mergeSemanticsRestore: true,
    );
    expect(findings, hasLength(1));
    expect(findings.single.message, contains('runStartupMaintenance'));
  });

  test('runStartupMaintenance inside a string literal is a finding', () {
    writeConformantFixture();
    writeFile('lib/main.dart',
        "void main() { log('runStartupMaintenance()'); }\n");
    final findings = checkBackupConformance(
      root: root,
      mergeSemanticsRestore: true,
    );
    expect(findings, hasLength(1));
    expect(findings.single.message, contains('runStartupMaintenance'));
  });

  test('a reference without a call site does not satisfy maintenance', () {
    writeConformantFixture();
    writeFile('lib/main.dart',
        'const runStartupMaintenanceDocs = 1;\nvoid main() {}\n');
    final findings = checkBackupConformance(
      root: root,
      mergeSemanticsRestore: true,
    );
    expect(findings, hasLength(1));
    expect(findings.single.message, contains('runStartupMaintenance'));
  });

  test('confirm-copy overrides in comments do not satisfy a merge app', () {
    writeConformantFixture();
    writeFile('lib/backup_config.dart', '''
final backupConfig = BackupConfig(
  serializer: FixtureSerializer(),
  // confirmTitle: 'TODO', confirmActionLabel: 'TODO',
);
''');
    final findings = checkBackupConformance(
      root: root,
      mergeSemanticsRestore: true,
    );
    expect(findings, hasLength(2));
    expect(
      findings.map((f) => f.message).join('\n'),
      allOf(contains('confirmTitle'), contains('confirmActionLabel')),
    );
  });

  // --- the serializer must be a real declaration -----------------------

  test('a serializer declaration in a comment is not a serializer', () {
    writeConformantFixture();
    writeFile('lib/data/backup/serializer.dart',
        '// class FixtureSerializer implements BackupSerializer {}\n');
    final findings = checkBackupConformance(
      root: root,
      mergeSemanticsRestore: true,
    );
    expect(findings, hasLength(1));
    expect(
      findings.single.message,
      contains('no class under lib/ implements BackupSerializer'),
    );
  });

  test('BackupSerializerRegistry is not a BackupSerializer', () {
    // A superstring name must not satisfy the clause: the trailing word
    // boundary is what rejects it.
    writeConformantFixture();
    writeFile('lib/data/backup/serializer.dart', '''
class FixtureRegistry implements BackupSerializerRegistry {
  final items = <Object>[];
}
''');
    final findings = checkBackupConformance(
      root: root,
      mergeSemanticsRestore: true,
    );
    expect(findings, hasLength(1));
    expect(
      findings.single.message,
      contains('no class under lib/ implements BackupSerializer'),
    );
  });

  test('a dart-format wrapped declaration is still a serializer', () {
    // Every adopted app's declaration is >80 cols, so `dart format` wraps
    // the implements clause onto its own line:
    //   class LiltBackupSerializer
    //       implements BackupSerializer, PreviewableBackupSerializer {
    // The clause anchor must treat the wrapped header as ONE logical line
    // (stop at `{`/`;`, not at `\n`) or the whole fleet fails C2 for
    // conforming code.
    writeConformantFixture();
    writeFile('lib/data/backup/serializer.dart', '''
import 'package:sanctuary_backup_ui/sanctuary_backup_ui.dart';

class FixtureSerializer
    implements BackupSerializer, PreviewableBackupSerializer {
  String serialize() => BackupEnvelope.wrap('{}');
}
''');
    expect(
      checkBackupConformance(root: root, mergeSemanticsRestore: true),
      isEmpty,
    );
  });

  test('a clause match may not span lines into unrelated code', () {
    // `extends num> ... BackupSerializerFactory` used to satisfy the old
    // unanchored pattern across the newline; a declaration must sit on one
    // logical line.
    writeConformantFixture();
    writeFile('lib/data/backup/serializer.dart', '''
typedef Check<T extends num> = bool Function(T);
const dynamic ref = BackupSerializerFactory;
''');
    final findings = checkBackupConformance(
      root: root,
      mergeSemanticsRestore: true,
    );
    expect(findings, hasLength(1));
    expect(
      findings.single.message,
      contains('no class under lib/ implements BackupSerializer'),
    );
  });
}
