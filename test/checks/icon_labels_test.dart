import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oh_fleet_conformance/src/checks/icon_labels.dart';

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('ohfc_iconlabels_'));
  tearDown(() => root.deleteSync(recursive: true));

  List<String> scan(String body,
      {bool strict = false, Map<String, String> exemptions = const {}}) {
    File('${root.path}/lib/screen.dart')
      ..createSync(recursive: true)
      ..writeAsStringSync(body);
    return checkAppBarIconLabels(
            root: root, strict: strict, exemptions: exemptions)
        .map((f) => f.message)
        .toList();
  }

  // --- the real offender --------------------------------------------------

  test('a bare IconButton in AppBar actions is a finding naming file:line',
      () {
    final found = scan('''
Widget build(c) => Scaffold(
      appBar: AppBar(
        title: const Text('Timeline'),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: () {},
          ),
        ],
      ),
    );
''');
    expect(found, hasLength(1));
    expect(found.single, contains('lib/screen.dart:5'));
    expect(found.single, contains('label'));
    expect(found.single, contains('TextButton.icon'));
  });

  test('SliverAppBar actions are swept too', () {
    expect(scan('''
Widget b() => SliverAppBar(actions: [
      IconButton(icon: const Icon(Icons.search), onPressed: () {}),
    ]);
'''), hasLength(1));
  });

  test('OhIconButton and IconButton variants are swept', () {
    expect(scan('''
Widget b() => AppBar(actions: [
      OhIconButton.filled(icon: const Icon(Icons.add), onPressed: () {}),
      IconButton.outlined(icon: const Icon(Icons.share), onPressed: () {}),
    ]);
'''), hasLength(2));
  });

  test('an IconButton nested in a wrapper inside actions is still found', () {
    expect(scan('''
Widget b() => AppBar(actions: [
      Padding(
        padding: EdgeInsets.zero,
        child: IconButton(icon: const Icon(Icons.edit), onPressed: () {}),
      ),
    ]);
'''), hasLength(1));
  });

  test('reports every offender, not just the first', () {
    expect(scan('''
Widget b() => AppBar(actions: [
      IconButton(icon: const Icon(Icons.a), onPressed: () {}),
      IconButton(icon: const Icon(Icons.b), onPressed: () {}),
    ]);
'''), hasLength(2));
  });

  // --- compliant shapes ---------------------------------------------------

  test('an IconButton with a tooltip passes (conservative floor)', () {
    expect(scan('''
Widget b() => AppBar(actions: [
      IconButton(
          tooltip: 'Filter', icon: const Icon(Icons.a), onPressed: () {}),
    ]);
'''), isEmpty);
  });

  test('an icon with a visible Text label passes', () {
    expect(scan('''
Widget b() => AppBar(actions: [
      TextButton.icon(
          onPressed: () {}, icon: const Icon(Icons.a), label: const Text('Filter')),
      IconButton(
          onPressed: () {},
          icon: Column(children: const [Icon(Icons.b), Text('Share')])),
    ]);
'''), isEmpty);
  });

  test('a PopupMenuButton (the worded menu) is compliant', () {
    expect(scan('''
Widget b() => AppBar(actions: [
      PopupMenuButton<int>(itemBuilder: (c) => const []),
    ]);
'''), isEmpty);
  });

  test('an IconButton outside actions is out of scope', () {
    expect(scan('''
Widget b() => Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.close), onPressed: () {}),
      ),
      body: IconButton(icon: const Icon(Icons.add), onPressed: () {}),
    );
'''), isEmpty);
  });

  test('a commented-out IconButton is not a finding', () {
    expect(scan('''
Widget b() => AppBar(actions: [
      // IconButton(icon: const Icon(Icons.a), onPressed: () {}),
    ]);
'''), isEmpty);
  });

  // --- cannot pass by finding nothing -------------------------------------

  test('no Dart sources under lib/ is a finding', () {
    expect(checkAppBarIconLabels(root: root), isNotEmpty);
  });

  test('no AppBar or SliverAppBar anywhere is a finding, not a pass', () {
    expect(scan('const x = 1;\n').single, contains('AppBar'));
  });

  // --- strict mode (opt-in: FleetCheck.c11StrictBarLabels) ----------------

  group('strict', () {
    test('a tooltip no longer passes: the word must be on screen', () {
      final found = scan('''
Widget b() => AppBar(actions: [
      IconButton(
          tooltip: 'Filter', icon: const Icon(Icons.a), onPressed: () {}),
    ]);
''', strict: true);
      expect(found, hasLength(1));
      expect(found.single, contains('lib/screen.dart:2'));
      expect(found.single, contains('OhBarAction'));
    });

    test('an icon-only PopupMenuButton is a finding; OhBarOverflow passes',
        () {
      final found = scan('''
Widget b() => AppBar(actions: [
      PopupMenuButton<String>(tooltip: 'More', itemBuilder: (c) => const []),
      OhBarOverflow<String>(itemBuilder: (c) => const []),
    ]);
''', strict: true);
      expect(found, hasLength(1));
      expect(found.single, contains('PopupMenuButton'));
      expect(found.single, contains('OhBarOverflow'));
    });

    test('a PopupMenuButton whose child shows a word passes', () {
      expect(scan('''
Widget b() => AppBar(actions: [
      PopupMenuButton<int>(
        itemBuilder: (c) => const [],
        child: Row(children: const [Icon(Icons.more_vert), Text('More')]),
      ),
    ]);
''', strict: true), isEmpty);
    });

    test('OhBarAction, TextButton.icon and a worded icon pass', () {
      expect(scan('''
Widget b() => AppBar(actions: [
      OhBarActions(children: [
        OhBarAction(icon: Icons.refresh, label: 'Refresh', onPressed: () {}),
      ]),
      TextButton.icon(
          onPressed: () {}, icon: const Icon(Icons.a), label: const Text('Go')),
      IconButton(
          onPressed: () {},
          icon: Column(children: const [Icon(Icons.b), Text('Share')])),
    ]);
''', strict: true), isEmpty);
    });

    test('an IconButton inside OhBarActions is still swept', () {
      expect(scan('''
Widget b() => AppBar(actions: [
      OhBarActions(children: [
        IconButton(tooltip: 'x', icon: const Icon(Icons.a), onPressed: () {}),
      ]),
    ]);
''', strict: true), hasLength(1));
    });

    test('the default mode still accepts the tooltip floor', () {
      expect(scan('''
Widget b() => AppBar(actions: [
      IconButton(tooltip: 'x', icon: const Icon(Icons.a), onPressed: () {}),
      PopupMenuButton<String>(tooltip: 'More', itemBuilder: (c) => const []),
    ]);
'''), isEmpty);
    });

    test('cannot pass by finding nothing', () {
      expect(checkAppBarIconLabels(root: root, strict: true), isNotEmpty);
    });

    const picker = '''
Widget b() => AppBar(actions: [
      PopupMenuButton<int>(
        key: const Key('mode-toggle'),
        itemBuilder: (c) => const [],
        child: _Face(label: mode),
      ),
    ]);
''';

    test('a keyed control can be exempted with a reason', () {
      expect(scan(picker, strict: true), hasLength(1));
      expect(
          scan(picker,
              strict: true,
              exemptions: {
                'lib/screen.dart#mode-toggle': 'face shows the word in _Face'
              }),
          isEmpty);
    });

    test('an exemption with no reason is a finding', () {
      final found = scan(picker,
          strict: true, exemptions: {'lib/screen.dart#mode-toggle': ' '});
      expect(found.single, contains('reason'));
    });

    test('an exemption that matches nothing is a finding', () {
      final found = scan(picker, strict: true, exemptions: {
        'lib/screen.dart#mode-toggle': 'real',
        'lib/screen.dart#gone': 'stale',
      });
      expect(found.single, contains('lib/screen.dart#gone'));
    });
  });
}
