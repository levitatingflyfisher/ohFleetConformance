import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oh_fleet_conformance/src/checks/raw_errors.dart';

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('ohfc_rawerr_'));
  tearDown(() => root.deleteSync(recursive: true));

  void write(String relative, String content) => File('${root.path}/$relative')
    ..createSync(recursive: true)
    ..writeAsStringSync(content);

  List<String> scan(String body) {
    write('lib/screen.dart', body);
    return checkNoRawErrorText(root: root).map((f) => f.message).toList();
  }

  // --- the real offenders (Lilt finding 5, Peckish, StillLife) -------------

  test("Text('Error: \$e') in an AsyncValue error builder is a finding", () {
    final found = scan(r'''
Widget build(c, ref) => ref.watch(p).when(
      data: (d) => const Home(),
      loading: () => const Spinner(),
      error: (e, st) => Center(child: Text('Error: $e')),
    );
''');
    expect(found, hasLength(1));
    expect(found.single, contains('lib/screen.dart:4'));
    expect(found.single, contains('OhErrorState'));
    expect(found.single, contains('ohFriendlyErrorMessage'));
  });

  test("a SnackBar with Text('Import failed: \$e') in a catch is a finding",
      () {
    final found = scan(r'''
Future<void> f(messenger) async {
  try {
    await import();
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Import failed: $e')));
  }
}
''');
    expect(found.single, contains('lib/screen.dart:5'));
  });

  test('e.toString() as the text is a finding', () {
    expect(scan(r'''
void f() {
  try {} on FormatException catch (e) {
    show(Text(e.toString()));
  }
}
'''), hasLength(1));
  });

  test("'\${snapshot.error}' is a finding without needing a binding", () {
    expect(scan(r'''
Widget b(c, snapshot) => Text('Failed: ${snapshot.error}');
'''), hasLength(1));
  });

  test("'\$error' and '\${err}' are findings", () {
    expect(scan(r'''
Widget a(error) => Text('Something broke: $error');
Widget b(err) => Text('${err}');
'''), hasLength(2));
  });

  test('SelectableText, TextSpan(text:) and errorText: are all surfaces', () {
    expect(scan(r'''
void f() {
  try {} catch (e) {
    a(SelectableText('$e'));
    b(TextSpan(text: 'x $e'));
    c(InputDecoration(errorText: e.toString()));
  }
}
'''), hasLength(3));
  });

  test('reports every offender, not just the first', () {
    expect(scan(r'''
Widget a(error) => Text('$error');
Widget b(error) => Text(error.toString());
'''), hasLength(2));
  });

  // --- not errors -----------------------------------------------------------

  test('an e that is not bound as an error is not flagged', () {
    // `.map((e) => ...)` over a list of labels: e is a list element.
    expect(scan(r'''
Widget f(List<String> labels) =>
    Column(children: labels.map((e) => Text('$e')).toList());
'''), isEmpty);
  });

  test('a friendly message from ohFriendlyErrorMessage is not flagged', () {
    expect(scan(r'''
void f() {
  try {} catch (e) {
    show(Text(ohFriendlyErrorMessage(e)));
  }
}
'''), isEmpty);
  });

  test('identifiers that merely start with error are not errors', () {
    expect(scan(r'''
Widget f(int errorCount) => Text('$errorCount problems');
'''), isEmpty);
  });

  test('a mention in a comment is not a finding', () {
    expect(scan(r'''
// never do Text('Error: $error')
Widget ok() => const Text('hi');
'''), isEmpty);
  });

  test('a raw error sent to a logger, not a widget, is not flagged', () {
    expect(scan(r'''
void f() {
  try {} catch (e) {
    debugPrint('load failed: $e');
    log(e.toString());
  }
}
Widget ok() => const Text('hi');
'''), isEmpty);
  });

  test('generated sources are skipped', () {
    write('lib/ok.dart', "Widget ok() => const Text('hi');\n");
    write('lib/model.g.dart', r"Widget a(error) => Text('$error');" '\n');
    expect(checkNoRawErrorText(root: root), isEmpty);
  });

  // --- cannot pass by finding nothing ---------------------------------------

  test('no Dart sources under lib/ is a finding', () {
    expect(checkNoRawErrorText(root: root), isNotEmpty);
  });

  test('sources with no Text widget at all is a finding (nothing swept)', () {
    expect(scan('const x = 1;\n').single, contains('no Text'));
  });
}
