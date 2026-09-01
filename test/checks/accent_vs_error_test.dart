import 'dart:io';

import 'package:flutter/material.dart' show Brightness;
import 'package:flutter_test/flutter_test.dart';
import 'package:oh_fleet_conformance/src/checks/accent_vs_error.dart';

void main() {
  late Directory parent;
  late Directory app;
  late Directory design;

  void write(Directory base, String relative, String content) =>
      File('${base.path}/$relative')
        ..createSync(recursive: true)
        ..writeAsStringSync(content);

  // The real ohStyle 0.7.0 values: warmth hearth500 is ΔE00 ~14 from
  // urgency red500, so the palette's own default is a live test case.
  void writeDesign() {
    write(design, 'lib/src/colors.dart', '''
abstract final class OhColors {
  static const hearth400 = Color(0xFFCD8366);
  static const hearth500 = Color(0xFF9E4D2C);
  static const sage400 = Color(0xFF7BAF96);
  static const sky500 = Color(0xFF3D82C9);
  static const red300 = Color(0xFFFF939C);
  static const red500 = Color(0xFF9B1D29);
}
''');
    write(design, 'lib/src/color_roles.dart', '''
class OhColorRoles {
  static const light = OhColorRoles(
    warmth: OhColors.hearth500,
    urgency: OhColors.red500,
  );
  static const hearthDark = OhColorRoles(
    warmth: OhColors.hearth400,
    urgency: OhColors.red300,
  );
  static const night = OhColorRoles(
    warmth: OhColors.sage400,
    urgency: OhColors.red300,
  );
}
''');
  }

  setUp(() {
    parent = Directory.systemTemp.createTempSync('ohfc_accent_');
    app = Directory('${parent.path}/app')..createSync();
    design = Directory('${parent.path}/design');
    writeDesign();
  });
  tearDown(() => parent.deleteSync(recursive: true));

  List<String> run({List<FleetAccent> declared = const []}) =>
      checkAccentVsError(root: app, designPackage: design, declared: declared)
          .map((f) => f.message)
          .toList();

  void theme(String body) => write(app, 'lib/theme.dart', body);

  // --- declared accents ----------------------------------------------------

  test('a declared light accent far from the error red passes', () {
    expect(run(declared: const [FleetAccent.light(0xFF3D82C9)]), isEmpty);
  });

  test('a declared light accent too close to the light error red is a finding',
      () {
    // A crimson 1.2 ΔE00 from red500: an accent that IS the error colour.
    final found = run(declared: const [FleetAccent.light(0xFFA0202C)]);
    expect(found, hasLength(1));
    expect(found.single, contains('0xFFA0202C'));
    expect(found.single, contains('0xFF9B1D29'));
    expect(found.single, contains('CIEDE2000'));
    expect(found.single, contains('12'));
  });

  test("ohStyle 0.7.0's own warmth passes: 14.1 (light) and 16.6 (dark) "
      'clear 12 — the ruling lets red be warmth and error, told apart by '
      'icon and word', () {
    expect(
        run(declared: const [
          FleetAccent.light(0xFF9E4D2C),
          FleetAccent.dark(0xFFCD8366),
        ]),
        isEmpty);
  });

  test('a failing finding carries the colour-blind simulation as a note', () {
    final found = run(declared: const [FleetAccent.light(0xFFA0202C)]);
    expect(found.single, contains('colour-blind'));
    expect(found.single, contains('deuteranopia'));
  });

  test('an accent distinct in normal vision but merged for a dichromat is '
      'NOT a failure — urgency always carries an icon and a word', () {
    // Yolk vs the dark urgency: ~34 ΔE00 normally, ~6 under tritanopia.
    expect(run(declared: const [FleetAccent.dark(0xFFF2A93B)]), isEmpty);
  });

  test('accents are compared only with the error red of their own theme', () {
    // Yolk is close to the DARK urgency (see above) but a light accent never
    // shares a screen with it; against light red500 it is far apart.
    expect(run(declared: const [FleetAccent.light(0xFFF2A93B)]), isEmpty);
  });

  test('declared accents replace detection: unresolvable code is not asked '
      'about', () {
    theme('ThemeData t(Color seed) => ThemeData(colorScheme: '
        'ColorScheme.fromSeed(seedColor: seed));\n');
    expect(run(declared: const [FleetAccent.light(0xFF3D82C9)]), isEmpty);
  });

  // --- detection from the app's theme code --------------------------------

  test('fromSeed is judged by the RENDERED primary, not the seed', () {
    theme('final t = ThemeData(colorScheme: '
        'ColorScheme.fromSeed(seedColor: Color(0xFF9B1D29)));\n');
    final found = run();
    expect(found, isNotEmpty);
    expect(found.first, contains('fromSeed'));
    expect(found.first, isNot(contains('0xFF9B1D29 (light')));
  });

  test('a far seed resolved through an app colour class passes', () {
    write(app, 'lib/colors.dart',
        'abstract final class AppColors {\n'
        '  static const sky = Color(0xFF3D82C9);\n}\n');
    theme('final t = ThemeData(colorScheme: '
        'ColorScheme.fromSeed(seedColor: AppColors.sky));\n');
    expect(run(), isEmpty);
  });

  test('brightness: Brightness.dark pairs the accent with the dark red', () {
    theme('final t = ColorScheme.fromSeed(\n'
        '    seedColor: Color(0xFF3D82C9), brightness: Brightness.dark);\n');
    expect(run(), isEmpty);
  });

  test('an explicit primary: wins over the seed, including via copyWith', () {
    theme('final a = ColorScheme.fromSeed(seedColor: Color(0xFF3D82C9))\n'
        '    .copyWith(primary: Color(0xFFA0202C));\n');
    expect(run().first, contains('0xFFA0202C'));
  });

  test('ColorScheme.light(primary:) is read directly', () {
    theme('final s = ColorScheme.light(primary: Color(0xFFA0202C));\n');
    expect(run().first, contains('0xFFA0202C'));
  });

  test("OhTheme.light() with no appAccent is ohStyle's own warmth — which "
      'the check measures like any other accent', () {
    theme('final t = OhTheme.light();\n');
    // The real 0.7.0 warmth passes...
    expect(run(), isEmpty);
    // ...and the role IS what is measured: point warmth at the error red.
    write(design, 'lib/src/color_roles.dart', '''
class OhColorRoles {
  static const light = OhColorRoles(
    warmth: OhColors.red500,
    urgency: OhColors.red500,
  );
}
''');
    final found = run();
    expect(found, isNotEmpty);
    expect(found.first, contains('OhTheme.light'));
  });

  test('OhTheme.light(appAccent:) uses the app accent as-is', () {
    theme('const accent = OhColors.sky500;\n'
        'final t = OhTheme.light(appAccent: accent);\n');
    expect(run(), isEmpty);
  });

  test('an accent expression C12 cannot resolve is a finding', () {
    theme('ThemeData t(Color seed) => ThemeData(colorScheme: '
        'ColorScheme.fromSeed(seedColor: seed));\n');
    final found = run();
    expect(found.single, contains('seed'));
    expect(found.single, contains('accentColors'));
  });

  test('a commented-out theme is not detected', () {
    theme('// final s = ColorScheme.light(primary: Color(0xFFA0202C));\n'
        'final s = ColorScheme.light(primary: Color(0xFF3D82C9));\n');
    expect(run(), isEmpty);
  });

  // --- cannot pass by finding nothing -------------------------------------

  test('no accent detected and none declared is a finding', () {
    theme('const x = 1;\n');
    expect(run().single, contains('no accent'));
  });

  test('a missing design package is a finding, not a pass', () {
    design.deleteSync(recursive: true);
    expect(run(declared: const [FleetAccent.light(0xFF3D82C9)]), isNotEmpty);
  });

  test('roles with no urgency parsed is a finding', () {
    write(design, 'lib/src/color_roles.dart', 'class OhColorRoles {}\n');
    expect(run(declared: const [FleetAccent.light(0xFF3D82C9)]).single,
        contains('urgency'));
  });

  test('an accent whose theme has no urgency role is a finding, not a pass',
      () {
    write(design, 'lib/src/color_roles.dart', '''
class OhColorRoles {
  static const light = OhColorRoles(urgency: OhColors.red500);
}
''');
    final found = run(declared: const [FleetAccent.dark(0xFF3D82C9)]);
    expect(found.single, contains('dark'));
    expect(found.single, contains('urgency'));
  });

  test('FleetAccent carries its brightness', () {
    expect(const FleetAccent.dark(0xFF000000).brightness, Brightness.dark);
  });
}
