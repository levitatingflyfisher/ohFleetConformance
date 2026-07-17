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
