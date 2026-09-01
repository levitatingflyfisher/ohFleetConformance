import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oh_fleet_conformance/src/checks/primary_screens.dart';

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('ohfc_primary_'));
  tearDown(() => root.deleteSync(recursive: true));

  void write(String relative, String content) => File('${root.path}/$relative')
    ..createSync(recursive: true)
    ..writeAsStringSync(content);

  List<String> run(Set<String> screens) =>
      checkPrimaryScreenSweeps(root: root, screens: screens)
          .map((f) => f.message)
          .toList();

  void screen(String name) => write('lib/${name.toLowerCase()}.dart',
      'class $name extends StatelessWidget {}\n');

  const sweptOnboarding = '''
void main() {
  testWidgets('onboarding survives 360 x 1.3', (tester) async {
    await runPrimaryActionSweep(
      tester,
      primaryAction: find.text('Get started'),
      pumpScreen: () => tester.pumpWidget(wrap(const OnboardingScreen())),
    );
  });
}
''';

  test('a listed screen swept by runPrimaryActionSweep passes', () {
    screen('OnboardingScreen');
    write('test/onboarding_a11y_test.dart', sweptOnboarding);
    expect(run({'OnboardingScreen'}), isEmpty);
  });

  test('a listed screen with no primary-action sweep is a finding', () {
    screen('OnboardingScreen');
    screen('TodayScreen');
    write('test/onboarding_a11y_test.dart', sweptOnboarding);
    final found = run({'OnboardingScreen', 'TodayScreen'});
    expect(found.single, contains('TodayScreen'));
    expect(found.single, contains('runPrimaryActionSweep'));
    expect(found.single, contains('360'));
  });

  test('the screen must be INSIDE the sweep call, not just in the same file',
      () {
    screen('TodayScreen');
    write('test/today_test.dart', '''
void main() {
  testWidgets('renders', (tester) async {
    await tester.pumpWidget(const TodayScreen());
  });
  testWidgets('sweep something else', (tester) async {
    await runPrimaryActionSweep(tester,
        primaryAction: find.text('Go'),
        pumpScreen: () => tester.pumpWidget(const OtherScreen()));
  });
}
''');
    expect(run({'TodayScreen'}).single, contains('TodayScreen'));
  });

  test('the old 320 x 3.0 sweep alone does not satisfy the profile', () {
    screen('TodayScreen');
    write('test/today_test.dart', '''
void main() {
  testWidgets('a11y', (tester) async {
    await runA11ySweep(tester,
        pumpScreen: () => tester.pumpWidget(const TodayScreen()));
  });
}
''');
    expect(run({'TodayScreen'}), hasLength(1));
  });

  test('a commented-out sweep does not count', () {
    screen('TodayScreen');
    write('test/today_test.dart', '''
// await runPrimaryActionSweep(tester, pumpScreen: () => tester.pumpWidget(const TodayScreen()));
void main() {}
''');
    expect(run({'TodayScreen'}), hasLength(1));
  });

  test('a listed screen with no class in lib/ is a stale entry', () {
    write('test/onboarding_a11y_test.dart', sweptOnboarding);
    screen('OnboardingScreen');
    expect(run({'OnboardingScreen', 'GoneScreen'}).single,
        contains('GoneScreen'));
  });

  test('an empty screen list is a finding, not a pass', () {
    screen('OnboardingScreen');
    expect(run(const {}).single, contains('primaryActionScreens'));
  });
}
