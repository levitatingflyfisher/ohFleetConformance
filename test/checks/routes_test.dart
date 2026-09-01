import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oh_fleet_conformance/src/checks/routes.dart';

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('ohfc_routes_'));
  tearDown(() => root.deleteSync(recursive: true));

  void write(String relative, String content) => File('${root.path}/$relative')
    ..createSync(recursive: true)
    ..writeAsStringSync(content);

  List<String> messages([Map<String, String> exemptions = const {}]) =>
      checkRouteReachability(root: root, exemptions: exemptions)
          .map((f) => f.message)
          .toList();

  const router = '''
final router = GoRouter(
  initialLocation: '/home',
  routes: [
    GoRoute(path: '/home', builder: (c, s) => const Home()),
    GoRoute(path: '/settings', builder: (c, s) => const Settings()),
    GoRoute(path: '/item/:id', builder: (c, s) => Item(s.pathParameters['id']!)),
  ],
);
''';

  // --- the real offender --------------------------------------------------

  test('a declared route nobody navigates to is a finding naming it', () {
    write('lib/app/router.dart', router);
    write('lib/home.dart', "void f(c) => c.push('/settings');\n");
    final found = messages();
    expect(found, hasLength(1));
    expect(found.single, contains("'/item/:id'"));
    expect(found.single, contains('lib/app/router.dart:6'));
    expect(found.single, contains('routeExemptions'));
  });

  test('an interpolated call reaches a parameterised route', () {
    write('lib/app/router.dart', router);
    write('lib/home.dart', '''
void f(c, id) {
  c.push('/settings');
  c.push('/item/\$id?from=home');
}
''');
    expect(messages(), isEmpty);
  });

  test('a path literal in a helper or tab list counts as a way in', () {
    write('lib/app/router.dart', router);
    write('lib/nav.dart', '''
const tabs = ['/settings'];
String itemPath(String id) => '/item/\${id}';
''');
    expect(messages(), isEmpty);
  });

  test('a mention in a comment is not a way in', () {
    write('lib/app/router.dart', router);
    write('lib/home.dart', '''
// reached via c.push('/settings') from the drawer
void f(c) => c.push('/item/1');
''');
    expect(messages().single, contains("'/settings'"));
  });

  test('the declaration itself is not its own way in', () {
    write('lib/app/router.dart', router);
    write('lib/home.dart', "void f(c) => c.push('/item/1');\n");
    expect(messages().single, contains("'/settings'"));
  });

  // --- nesting, names, shells ---------------------------------------------

  test('a relative child path is joined to its parent', () {
    write('lib/app/router.dart', '''
final router = GoRouter(routes: [
  GoRoute(path: '/', builder: (c, s) => const Home(), routes: [
    GoRoute(path: 'rooms', builder: (c, s) => const Rooms(), routes: [
      GoRoute(path: ':roomId', builder: (c, s) => const Room()),
    ]),
  ]),
]);
''');
    write('lib/home.dart', "void f(c) => c.go('/rooms');\n");
    final found = messages();
    expect(found.single, contains("'/rooms/:roomId'"));
  });

  test('a named route is reached by goNamed/pushNamed with its name', () {
    write('lib/app/router.dart', '''
final router = GoRouter(routes: [
  GoRoute(path: '/', name: 'home', builder: (c, s) => const Home(), routes: [
    GoRoute(path: 'add', name: 'addItem', builder: (c, s) => const Add()),
  ]),
]);
''');
    write('lib/home.dart', "void f(c) => c.pushNamed('addItem');\n");
    expect(messages(), isEmpty);
  });

  test('a bare string equal to a route name is not a named call', () {
    write('lib/app/router.dart', '''
final router = GoRouter(routes: [
  GoRoute(path: '/', builder: (c, s) => const Home(), routes: [
    GoRoute(path: 'add', name: 'addItem', builder: (c, s) => const Add()),
  ]),
]);
''');
    write('lib/prefs.dart', "const key = 'addItem';\n");
    expect(messages().single, contains("'/add'"));
  });

  test('stateful shell branch roots are reached through goBranch', () {
    const shell = '''
final router = GoRouter(routes: [
  StatefulShellRoute.indexedStack(
    builder: (c, s, shell) => Shell(shell),
    branches: [
      StatefulShellBranch(routes: [
        GoRoute(path: '/today', builder: (c, s) => const Today(), routes: [
          GoRoute(path: 'detail', builder: (c, s) => const Detail()),
        ]),
      ]),
      StatefulShellBranch(routes: [
        GoRoute(path: '/stats', builder: (c, s) => const Stats()),
      ]),
    ],
  ),
]);
''';
    write('lib/app/router.dart', shell);
    write('lib/shell.dart', 'void tap(s, i) => s.goBranch(i);\n');
    // The branch roots are exempt; the nested detail route is not.
    expect(messages().single, contains("'/today/detail'"));
  });

  test('without goBranch, branch roots need a way in like any route', () {
    write('lib/app/router.dart', '''
final router = GoRouter(routes: [
  StatefulShellRoute.indexedStack(branches: [
    StatefulShellBranch(routes: [
      GoRoute(path: '/today', builder: (c, s) => const Today()),
    ]),
  ]),
]);
''');
    write('lib/shell.dart', 'const x = 1;\n');
    expect(messages().single, contains("'/today'"));
  });

  test('the root route is go_router\'s default location without initialLocation',
      () {
    write('lib/app/router.dart', '''
final router = GoRouter(routes: [
  GoRoute(path: '/', builder: (c, s) => const Home()),
]);
''');
    write('lib/home.dart', 'const x = 1;\n');
    expect(messages(), isEmpty);
  });

  test('initialLocation is a way in', () {
    write('lib/app/router.dart', router);
    write('lib/home.dart',
        "void f(c) { c.push('/settings'); c.push('/item/1'); }\n");
    // '/home' is only named by initialLocation — that is a real door.
    expect(messages(), isEmpty);
  });

  test('a redirect-only route is not a screen and needs no door', () {
    write('lib/app/router.dart', '''
final router = GoRouter(routes: [
  GoRoute(path: '/', builder: (c, s) => const Home()),
  GoRoute(path: '/old-name', redirect: (_, __) => '/'),
]);
''');
    write('lib/home.dart', 'const x = 1;\n');
    expect(messages(), isEmpty);
  });

  // --- exemptions ---------------------------------------------------------

  test('a recorded exemption with a reason clears the route', () {
    write('lib/app/router.dart', router);
    write('lib/home.dart', "void f(c) => c.push('/settings');\n");
    expect(messages({'/item/:id': 'deep link from the share sheet only'}),
        isEmpty);
  });

  test('an exemption without a reason is itself a finding', () {
    write('lib/app/router.dart', router);
    write('lib/home.dart', "void f(c) => c.push('/settings');\n");
    expect(messages({'/item/:id': '  '}).single, contains('reason'));
  });

  test('an exemption for an undeclared route is a stale finding', () {
    write('lib/app/router.dart', router);
    write('lib/home.dart',
        "void f(c) { c.push('/settings'); c.push('/item/1'); }\n");
    expect(messages({'/gone': 'was a deep link'}).single,
        contains("'/gone'"));
  });

  test('an exemption for a route that now has a door is a finding', () {
    write('lib/app/router.dart', router);
    write('lib/home.dart',
        "void f(c) { c.push('/settings'); c.push('/item/1'); }\n");
    expect(messages({'/item/:id': 'deep link'}).single,
        contains('no longer needed'));
  });

  // --- cannot pass by finding nothing -------------------------------------

  test('no Dart sources under lib/ is a finding', () {
    expect(messages(), isNotEmpty);
  });

  test('no GoRoute declarations is a finding, not a pass', () {
    write('lib/main.dart', 'void main() {}\n');
    expect(messages().single, contains('GoRoute'));
  });

  test('a GoRoute whose path is not a literal is a finding', () {
    write('lib/app/router.dart', '''
final router = GoRouter(routes: [
  GoRoute(path: Routes.home, builder: (c, s) => const Home()),
]);
''');
    expect(messages().single, contains('not a string literal'));
  });

  test('generated sources neither declare nor reach routes', () {
    write('lib/app/router.dart', router);
    write('lib/home.dart', "void f(c) => c.push('/settings');\n");
    write('lib/home.g.dart', "void g(c) => c.push('/item/1');\n");
    expect(messages().single, contains("'/item/:id'"));
  });
}
