import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oh_fleet_conformance/src/checks/icon_buttons.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('ohfc_iconbuttons_');
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

  const dependingPubspec = '''
name: fixture_app
dependencies:
  flutter:
    sdk: flutter
  openhearth_design:
    path: ../ohStyle/openhearth_design
''';

  const notDependingPubspec = '''
name: fixture_app
dependencies:
  flutter:
    sdk: flutter
''';

  // --- the gate: apps not on openhearth_design are exempt ---------------

  test('an app that does not depend on openhearth_design is never flagged', () {
    writeFile('pubspec.yaml', notDependingPubspec);
    writeFile('lib/widget.dart', '''
import 'package:flutter/material.dart';

class Widget1 extends StatelessWidget {
  @override
  Widget build(BuildContext context) => IconButton.filled(
        onPressed: () {},
        icon: const Icon(Icons.add),
      );
}
''');
    expect(checkNoBareIconButtonVariants(root: root), isEmpty);
  });

  test('a missing pubspec.yaml is treated as no dependency, not a finding', () {
    // A real CALL SITE, not a bare tear-off: without the parens, deleting
    // the gate entirely would leave this test green for the wrong reason.
    writeFile('lib/widget.dart',
        "final x = IconButton.filled(onPressed: (){}, icon: const Icon(0));\n");
    expect(checkNoBareIconButtonVariants(root: root), isEmpty);
  });

  // --- the real offender --------------------------------------------------

  test('a bare IconButton.filled( call is a finding naming file and line', () {
    writeFile('pubspec.yaml', dependingPubspec);
    writeFile('lib/widgets/save_button.dart', '''
import 'package:flutter/material.dart';

class SaveButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return IconButton.filled(
      onPressed: () {},
      icon: const Icon(Icons.check),
    );
  }
}
''');
    final findings = checkNoBareIconButtonVariants(root: root);
    expect(findings, hasLength(1));
    expect(findings.single.check, 'C8-iconButtons');
    expect(findings.single.message, contains('lib/widgets/save_button.dart:6'));
    expect(findings.single.message, contains('IconButton.filled('));
    expect(findings.single.message, contains('OhIconButton.filled'));
    expect(findings.single.message, contains('openhearth_design'));
  });

  test('a bare IconButton.filledTonal( call is a finding naming its own fix',
      () {
    writeFile('pubspec.yaml', dependingPubspec);
    writeFile('lib/widgets/mute_button.dart', '''
import 'package:flutter/material.dart';

final muteButton = IconButton.filledTonal(
  onPressed: () {},
  icon: const Icon(Icons.mic_off),
);
''');
    final findings = checkNoBareIconButtonVariants(root: root);
    expect(findings, hasLength(1));
    expect(findings.single.message, contains('lib/widgets/mute_button.dart:3'));
    expect(findings.single.message, contains('IconButton.filledTonal('));
    expect(findings.single.message, contains('OhIconButton.filledTonal'));
  });

  test('reports every offender, not just the first', () {
    writeFile('pubspec.yaml', dependingPubspec);
    writeFile('lib/a.dart',
        "final a = IconButton.filled(onPressed: (){}, icon: const Icon(0));\n");
    writeFile('lib/b.dart',
        "final b = IconButton.filledTonal(onPressed: (){}, icon: const Icon(0));\n");
    expect(checkNoBareIconButtonVariants(root: root), hasLength(2));
  });

  // --- the wrapper itself must never be flagged ---------------------------

  test('OhIconButton.filled( is not flagged — it is the fix, not the bug', () {
    writeFile('pubspec.yaml', dependingPubspec);
    writeFile('lib/widget.dart', '''
import 'package:openhearth_design/openhearth_design.dart';

final ok = OhIconButton.filled(onPressed: () {}, icon: const Icon(0));
''');
    expect(checkNoBareIconButtonVariants(root: root), isEmpty);
  });

  test('OhIconButton.filledTonal( is not flagged', () {
    writeFile('pubspec.yaml', dependingPubspec);
    writeFile('lib/widget.dart', '''
final ok = OhIconButton.filledTonal(onPressed: () {}, icon: const Icon(0));
''');
    expect(checkNoBareIconButtonVariants(root: root), isEmpty);
  });

  test('a library-prefixed bare call is still caught', () {
    // `material.IconButton.filled(` is still the bare Flutter constructor —
    // an import prefix does not make it OhIconButton.
    writeFile('pubspec.yaml', dependingPubspec);
    writeFile('lib/widget.dart', '''
import 'package:flutter/material.dart' as material;

final btn = material.IconButton.filled(onPressed: () {}, icon: const Icon(0));
''');
    expect(checkNoBareIconButtonVariants(root: root), hasLength(1));
  });

  // --- lib/ only, never test/ ---------------------------------------------

  test(
      'a bare call under test/ is never flagged — a collision regression '
      'test must be free to construct one', () {
    writeFile('pubspec.yaml', dependingPubspec);
    writeFile('lib/widget.dart', "const clean = 1;\n");
    writeFile('test/icon_button_collision_test.dart', '''
import 'package:flutter/material.dart';

void main() {
  final bare = IconButton.filled(onPressed: () {}, icon: const Icon(0));
}
''');
    expect(checkNoBareIconButtonVariants(root: root), isEmpty);
  });

  // --- comment / string exclusion -----------------------------------------

  test('a mention in a comment is not a call site', () {
    writeFile('pubspec.yaml', dependingPubspec);
    writeFile('lib/widget.dart',
        '// TODO: migrate away from IconButton.filled(\nconst clean = 1;\n');
    expect(checkNoBareIconButtonVariants(root: root), isEmpty);
  });

  test('a mention inside a string literal is not a call site', () {
    writeFile('pubspec.yaml', dependingPubspec);
    writeFile('lib/widget.dart', "const label = 'avoid IconButton.filled(';\n");
    expect(checkNoBareIconButtonVariants(root: root), isEmpty);
  });

  test('line numbers survive comment stripping', () {
    writeFile('pubspec.yaml', dependingPubspec);
    writeFile(
        'lib/widget.dart',
        '/* block\n   comment\n*/\n'
            'final x = IconButton.filled(onPressed: (){}, icon: const Icon(0));\n');
    final findings = checkNoBareIconButtonVariants(root: root);
    expect(findings, hasLength(1));
    expect(findings.single.message, contains('lib/widget.dart:4'));
  });

  // --- generated sources are build products, not authored code ------------

  test('generated .g.dart and .freezed.dart files are skipped', () {
    writeFile('pubspec.yaml', dependingPubspec);
    writeFile('lib/main.dart', 'const ok = 1;\n');
    writeFile('lib/model.g.dart',
        "final x = IconButton.filled(onPressed: (){}, icon: const Icon(0));\n");
    writeFile('lib/model.freezed.dart',
        "final y = IconButton.filledTonal(onPressed: (){}, icon: const Icon(0));\n");
    expect(checkNoBareIconButtonVariants(root: root), isEmpty);
  });

  // --- the check cannot pass vacuously -------------------------------------

  test('an app on openhearth_design with no Dart sources is a finding', () {
    writeFile('pubspec.yaml', dependingPubspec);
    expect(checkNoBareIconButtonVariants(root: root), isNotEmpty);
  });

  // --- the clean case -------------------------------------------------------

  test('a conformant app using only OhIconButton yields no findings', () {
    writeFile('pubspec.yaml', dependingPubspec);
    writeFile('lib/widgets/save_button.dart', '''
import 'package:openhearth_design/openhearth_design.dart';

class SaveButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) => OhIconButton.filled(
        onPressed: () {},
        icon: const Icon(Icons.check),
      );
}
''');
    expect(checkNoBareIconButtonVariants(root: root), isEmpty);
  });
}
