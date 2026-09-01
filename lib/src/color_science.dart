import 'dart:math' as math;

/// The colour maths behind C12: sRGB → CIELAB (D65), CIEDE2000, and
/// dichromat simulation. Pure functions over 0xAARRGGBB ints; alpha is
/// ignored.

/// A CIELAB colour (D65 white).
class Lab {
  final double l;
  final double a;
  final double b;
  const Lab(this.l, this.a, this.b);

  @override
  String toString() =>
      'Lab(${l.toStringAsFixed(1)}, ${a.toStringAsFixed(1)}, ${b.toStringAsFixed(1)})';
}

double _toLinear(int channel) {
  final c = channel / 255.0;
  return c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4) as double;
}

int _fromLinear(double v) {
  final c = v.clamp(0.0, 1.0);
  final s = c <= 0.0031308
      ? 12.92 * c
      : 1.055 * (math.pow(c, 1 / 2.4) as double) - 0.055;
  return (s * 255).round().clamp(0, 255);
}

List<double> _linearRgb(int argb) => [
      _toLinear((argb >> 16) & 0xFF),
      _toLinear((argb >> 8) & 0xFF),
      _toLinear(argb & 0xFF),
    ];

/// sRGB (0xAARRGGBB) to CIELAB, D65.
Lab labFromArgb(int argb) {
  final rgb = _linearRgb(argb);
  final r = rgb[0], g = rgb[1], b = rgb[2];
  final x = 0.4124564 * r + 0.3575761 * g + 0.1804375 * b;
  final y = 0.2126729 * r + 0.7151522 * g + 0.0721750 * b;
  final z = 0.0193339 * r + 0.1191920 * g + 0.9503041 * b;
  double f(double t) => t > 216 / 24389
      ? math.pow(t, 1 / 3) as double
      : (24389 / 27 * t + 16) / 116;
  final fx = f(x / 0.95047), fy = f(y / 1.0), fz = f(z / 1.08883);
  return Lab(116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz));
}

double _deg(double rad) => rad * 180 / math.pi;
double _rad(double deg) => deg * math.pi / 180;

/// CIEDE2000 colour difference (kL = kC = kH = 1), per Sharma, Wu & Dalal
/// (2005), whose reference pairs the tests pin.
double ciede2000(Lab c1, Lab c2) {
  final cb = (math.sqrt(c1.a * c1.a + c1.b * c1.b) +
          math.sqrt(c2.a * c2.a + c2.b * c2.b)) /
      2;
  final cb7 = math.pow(cb, 7);
  final g = 0.5 * (1 - math.sqrt(cb7 / (cb7 + math.pow(25, 7))));
  final a1p = (1 + g) * c1.a, a2p = (1 + g) * c2.a;
  final c1p = math.sqrt(a1p * a1p + c1.b * c1.b);
  final c2p = math.sqrt(a2p * a2p + c2.b * c2.b);
  double hue(double b, double ap) =>
      (b == 0 && ap == 0) ? 0 : (_deg(math.atan2(b, ap)) + 360) % 360;
  final h1p = hue(c1.b, a1p), h2p = hue(c2.b, a2p);

  final dLp = c2.l - c1.l;
  final dCp = c2p - c1p;
  double dhp;
  if (c1p * c2p == 0) {
    dhp = 0;
  } else {
    dhp = h2p - h1p;
    if (dhp > 180) dhp -= 360;
    if (dhp < -180) dhp += 360;
  }
  final dHp = 2 * math.sqrt(c1p * c2p) * math.sin(_rad(dhp / 2));

  final lbp = (c1.l + c2.l) / 2;
  final cbp = (c1p + c2p) / 2;
  double hbp;
  if (c1p * c2p == 0) {
    hbp = h1p + h2p;
  } else if ((h1p - h2p).abs() <= 180) {
    hbp = (h1p + h2p) / 2;
  } else if (h1p + h2p < 360) {
    hbp = (h1p + h2p + 360) / 2;
  } else {
    hbp = (h1p + h2p - 360) / 2;
  }
  final t = 1 -
      0.17 * math.cos(_rad(hbp - 30)) +
      0.24 * math.cos(_rad(2 * hbp)) +
      0.32 * math.cos(_rad(3 * hbp + 6)) -
      0.20 * math.cos(_rad(4 * hbp - 63));
  final dTheta = 30 * math.exp(-math.pow((hbp - 275) / 25, 2));
  final cbp7 = math.pow(cbp, 7);
  final rc = 2 * math.sqrt(cbp7 / (cbp7 + math.pow(25, 7)));
  final sl = 1 +
      0.015 * math.pow(lbp - 50, 2) / math.sqrt(20 + math.pow(lbp - 50, 2));
  final sc = 1 + 0.045 * cbp;
  final sh = 1 + 0.015 * cbp * t;
  final rt = -math.sin(_rad(2 * dTheta)) * rc;
  return math.sqrt(math.pow(dLp / sl, 2) +
      math.pow(dCp / sc, 2) +
      math.pow(dHp / sh, 2) +
      rt * (dCp / sc) * (dHp / sh));
}

/// The three dichromacies (full severity).
enum ColorVisionDeficiency { protanopia, deuteranopia, tritanopia }

/// Machado, Oliveira & Fernandes (2009), severity 1.0, applied in linear
/// sRGB.
const _machado = {
  ColorVisionDeficiency.protanopia: [
    [0.152286, 1.052583, -0.204868],
    [0.114503, 0.786281, 0.099216],
    [-0.003882, -0.048116, 1.051998],
  ],
  ColorVisionDeficiency.deuteranopia: [
    [0.367322, 0.860646, -0.227968],
    [0.280085, 0.672501, 0.047413],
    [-0.011820, 0.042940, 0.968881],
  ],
  ColorVisionDeficiency.tritanopia: [
    [1.255528, -0.076749, -0.178779],
    [-0.078411, 0.930809, 0.147602],
    [0.004733, 0.691367, 0.303900],
  ],
};

/// [argb] as a dichromat with [cvd] would see it (opaque result).
int simulateCvd(int argb, ColorVisionDeficiency cvd) {
  final m = _machado[cvd]!;
  final l = _linearRgb(argb);
  final out = [
    for (final row in m) row[0] * l[0] + row[1] * l[1] + row[2] * l[2],
  ];
  return 0xFF000000 |
      (_fromLinear(out[0]) << 16) |
      (_fromLinear(out[1]) << 8) |
      _fromLinear(out[2]);
}
