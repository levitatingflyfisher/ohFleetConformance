import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oh_fleet_conformance/oh_fleet_conformance.dart';

/// C14: on this Flutter, a SnackBar with an action persists until it is
/// tapped (`persist ??= action != null`), so a "Saved / Add notes" line
/// followed the person across screens for minutes (Lullaby, Sundial,
/// Peckish, Trellis). Every SnackBar with an action states persist.
void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('ohfc_snack_'));
  tearDown(() => root.deleteSync(recursive: true));

  void lib(String name, String src) {
    final f = File('${root.path}/lib/$name')..createSync(recursive: true);
    f.writeAsStringSync(src);
  }

  List<String> messages() =>
      [for (final f in checkSnackBarPersist(root: root)) f.message];

  test('an action without persist is a finding, with file and line', () {
    lib('a.dart', '''
void f(ctx) {
  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
    content: const Text('Saved'),
    action: SnackBarAction(label: 'Add notes', onPressed: () {}),
  ));
}
''');
    final m = messages();
    expect(m, hasLength(1));
    expect(m.single, allOf(contains('lib/a.dart:2'), contains('persist')));
  });

  test('an action with persist stated either way passes', () {
    lib('a.dart', '''
final a = SnackBar(content: Text('x'), persist: false,
    action: SnackBarAction(label: 'Edit', onPressed: () {}));
final b = SnackBar(content: Text('y'), action: SnackBarAction(label: 'Undo',
    onPressed: () {}), persist: true);
''');
    expect(messages(), isEmpty);
  });

  test('a SnackBar without an action needs nothing', () {
    lib('a.dart', "final a = SnackBar(content: Text('Saved'));\n");
    expect(messages(), isEmpty);
  });

  test('a nested call in the content does not hide the action', () {
    lib('a.dart', '''
final a = SnackBar(
  content: Text(label(x, y)),
  action: SnackBarAction(label: 'View', onPressed: () => go(a(b))),
);
''');
    expect(messages(), hasLength(1));
  });

  test('comments and strings that mention it are not call sites', () {
    lib('a.dart', '''
// A SnackBar(action: ...) persists; see C14.
const s = 'SnackBar(action: x)';
''');
    expect(messages(), isEmpty);
  });

  test('no Dart sources is a finding, not a pass', () {
    expect(messages().single, contains('no Dart sources'));
  });

  test('is wired as a check named C14-snackBarPersist', () {
    expect(FleetCheck.values, contains(FleetCheck.c14SnackBarPersist));
  });
}
