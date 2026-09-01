import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oh_fleet_conformance/oh_fleet_conformance.dart';

/// A rigid Row that fits at scale 1.0 in 320dp but overflows at 3.0 —
/// the fleet's canonical accessibility bug shape.
Widget rigidChipRow() => MaterialApp(
      home: Scaffold(
        body: Row(
          children: [
            const Text('Diapers today: 6, all clear'),
            Container(width: 40, height: 40, color: Colors.teal),
            const Text('more'),
          ],
        ),
      ),
    );

Widget responsiveChipRow() => MaterialApp(
      home: Scaffold(
        body: Row(
          children: [
            const Flexible(
              child: Text(
                'Diapers today: 6, all clear',
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(width: 40, height: 40, color: Colors.teal),
          ],
        ),
      ),
    );

void main() {
  primaryActionGroup();

  testWidgets('sweep surfaces a RenderFlex overflow at 3.0x/320dp',
      (tester) async {
    await runA11ySweep(
      tester,
      pumpScreen: () => tester.pumpWidget(rigidChipRow()),
    );
    final exception = tester.takeException();
    expect(exception, isNotNull,
        reason: 'the rigid row must overflow during the sweep');
    expect('$exception', contains('overflowed'));
  });

  testWidgets('sweep passes a responsive layout silently', (tester) async {
    await runA11ySweep(
      tester,
      pumpScreen: () => tester.pumpWidget(responsiveChipRow()),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('sweep actually applies 320dp and the requested text scales',
      (tester) async {
    final seenScales = <double>[];
    Size? seenSize;
    await runA11ySweep(
      tester,
      pumpScreen: () => tester.pumpWidget(
        MaterialApp(
          home: Builder(builder: (context) {
            final mq = MediaQuery.of(context);
            seenScales.add(mq.textScaler.scale(10) / 10);
            seenSize = mq.size;
            return const SizedBox();
          }),
        ),
      ),
    );
    expect(seenScales, [1.0, 3.0]);
    expect(seenSize, const Size(320, 640));
  });

  testWidgets('interact callback runs once per scale (opened-dialog surface)',
      (tester) async {
    var interactions = 0;
    await runA11ySweep(
      tester,
      pumpScreen: () => tester.pumpWidget(responsiveChipRow()),
      interact: () async => interactions++,
    );
    expect(interactions, 2);
  });
}

/// A primary action placed below the 640dp viewport with no scrollable to
/// bring it into view: present in the tree, never tappable.
Widget unreachablePrimary() => MaterialApp(
      home: Scaffold(
        body: Stack(
          children: [
            const Text('Welcome'),
            Positioned(
              top: 700,
              left: 0,
              child: FilledButton(onPressed: () {}, child: const Text('Start')),
            ),
          ],
        ),
      ),
    );

/// A primary action below the fold inside a scroll view: reachable.
Widget scrolledPrimary() => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Column(
            children: [
              const SizedBox(height: 900),
              FilledButton(onPressed: () {}, child: const Text('Start')),
            ],
          ),
        ),
      ),
    );

void primaryActionGroup() {
  group('runPrimaryActionSweep (360dp × 1.3, plus 320dp × 3.0)', () {
    test('the profiles are the ones the release gate names', () {
      expect(A11ySweepProfile.narrowLargeText.logicalSize, const Size(320, 640));
      expect(A11ySweepProfile.narrowLargeText.textScales, [1.0, 3.0]);
      expect(A11ySweepProfile.primaryAction.logicalSize, const Size(360, 640));
      expect(A11ySweepProfile.primaryAction.textScales, contains(1.3));
    });

    testWidgets('runs both profiles: 360dp at 1.3 and 320dp at 3.0',
        (tester) async {
      final seen = <(double, double)>[];
      await runPrimaryActionSweep(
        tester,
        primaryAction: find.byType(FilledButton),
        pumpScreen: () => tester.pumpWidget(MaterialApp(
          home: Builder(builder: (context) {
            final mq = MediaQuery.of(context);
            seen.add((mq.size.width, mq.textScaler.scale(10) / 10));
            return FilledButton(onPressed: () {}, child: const Text('Go'));
          }),
        )),
      );
      expect(seen, contains((360.0, 1.3)));
      expect(seen, contains((320.0, 3.0)));
    });

    testWidgets('a primary action off-screen with no way to scroll to it fails',
        (tester) async {
      // expectLater would race the sweep's own guarded pumps; catch instead.
      Object? failure;
      try {
        await runPrimaryActionSweep(
          tester,
          primaryAction: find.text('Start'),
          pumpScreen: () => tester.pumpWidget(unreachablePrimary()),
        );
      } on TestFailure catch (e) {
        failure = e;
      }
      expect(failure, isNotNull);
      expect('$failure', contains('360dp'));
    });

    testWidgets('a primary action below the fold in a scroll view passes',
        (tester) async {
      await runPrimaryActionSweep(
        tester,
        primaryAction: find.text('Start'),
        pumpScreen: () => tester.pumpWidget(scrolledPrimary()),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a primary action missing from the tree fails, not passes',
        (tester) async {
      // expectLater would race the sweep's own guarded pumps; catch instead.
      Object? failure;
      try {
        await runPrimaryActionSweep(
          tester,
          primaryAction: find.text('Start'),
          pumpScreen: () => tester.pumpWidget(responsiveChipRow()),
        );
      } on TestFailure catch (e) {
        failure = e;
      }
      expect(failure, isNotNull);
      expect('$failure', contains('360dp'));
    });
  });
}
