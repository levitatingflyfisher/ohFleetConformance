import 'package:flutter_test/flutter_test.dart';
import 'package:oh_fleet_conformance/src/color_science.dart';

void main() {
  group('CIEDE2000 against Sharma, Wu & Dalal (2005) reference pairs', () {
    // Pair numbers from the paper's Table 1.
    const pairs = [
      ([50.0, 2.6772, -79.7751], [50.0, 0.0, -82.7485], 2.0425), // #1
      ([50.0, 0.0, 0.0], [50.0, -1.0, 2.0], 2.3669), // #7
      ([50.0, 2.5, 0.0], [73.0, 25.0, -18.0], 27.1492), // #17
      ([60.2574, -34.0099, 36.2677], [60.4626, -34.1751, 39.4387],
          1.2644), // #25
    ];
    for (final (a, b, expected) in pairs) {
      test('$a vs $b = $expected', () {
        final d = ciede2000(Lab(a[0], a[1], a[2]), Lab(b[0], b[1], b[2]));
        expect(d, closeTo(expected, 1e-4));
      });
    }
  });

  test('sRGB white and black land at L* 100 and 0', () {
    expect(labFromArgb(0xFFFFFFFF).l, closeTo(100, 0.01));
    expect(labFromArgb(0xFF000000).l, closeTo(0, 0.01));
  });

  test('colour-vision simulation leaves greys grey', () {
    for (final cvd in ColorVisionDeficiency.values) {
      final grey = simulateCvd(0xFF808080, cvd);
      expect(ciede2000(labFromArgb(grey), labFromArgb(0xFF808080)),
          lessThan(1.0), reason: cvd.name);
    }
  });

  test('protanopia collapses a red/green pair that normal vision separates',
      () {
    const red = 0xFFD03030, green = 0xFF6C8C00;
    final normal = ciede2000(labFromArgb(red), labFromArgb(green));
    final protan = ciede2000(
      labFromArgb(simulateCvd(red, ColorVisionDeficiency.protanopia)),
      labFromArgb(simulateCvd(green, ColorVisionDeficiency.protanopia)),
    );
    expect(normal, greaterThan(40));
    expect(protan, lessThan(normal / 2));
  });
}
