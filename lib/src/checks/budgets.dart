import 'dart:convert';
import 'dart:io';

import '../findings.dart';

/// C3 — the size-budget ratchet.
///
/// The fleet's answer to bloat is measure-budget-ratchet, never cut
/// capability: every web build ships ~27MB of CanvasKit regardless, so the
/// JS payload is the part an app controls. Each app records baseline+5% in
/// `budgets.json`, and a regression fails CI here instead of accumulating
/// release over release.
///
/// The file itself is the ratchet's anchor: a missing `budgets.json` is a
/// finding (an app without recorded budgets can regress silently), and so
/// is a non-positive budget (the "temporarily zeroed" failure mode).
/// Absent build artifacts are NOT findings — a plain `flutter test` run
/// without a build must pass; the comparison bites only when artifacts are
/// on disk (CI after a build step, or the dev box after a deploy build).
List<ConformanceFinding> checkSizeBudgets({required Directory root}) {
  final budgetsFile = File('${root.path}/budgets.json');
  if (!budgetsFile.existsSync()) {
    return [
      const ConformanceFinding(
        _check,
        'budgets.json not found — record the app\'s size baselines '
        '(baseline+5% as main_dart_js_gz_max_bytes and apk_arm64_max_bytes) '
        'so size regressions fail CI instead of accumulating silently',
      ),
    ];
  }

  final Object? decoded;
  try {
    decoded = jsonDecode(budgetsFile.readAsStringSync());
  } on FormatException catch (e) {
    return [
      ConformanceFinding(_check, 'budgets.json is not valid JSON: ${e.message}'),
    ];
  }
  if (decoded is! Map<String, dynamic>) {
    return [
      ConformanceFinding(
        _check,
        'budgets.json must be a JSON object with main_dart_js_gz_max_bytes '
        'and apk_arm64_max_bytes, got ${decoded.runtimeType}',
      ),
    ];
  }
  // Extra keys are deliberately tolerated: apps record measurement notes
  // (dates, build ids) alongside the two budget keys.

  final findings = <ConformanceFinding>[];
  final jsBudget = _budget(decoded, 'main_dart_js_gz_max_bytes', findings);
  final apkBudget = _budget(decoded, 'apk_arm64_max_bytes', findings);

  final mainJs = File('${root.path}/build/web/main.dart.js');
  if (jsBudget != null && mainJs.existsSync()) {
    // The budget is on the wire size — servers ship this gzipped — so
    // compress in-memory rather than comparing the raw file length.
    _compare(
      findings,
      artifact: 'build/web/main.dart.js',
      actual: GZipCodec().encode(mainJs.readAsBytesSync()).length,
      unit: 'bytes gzipped',
      budget: jsBudget,
      key: 'main_dart_js_gz_max_bytes',
    );
  }

  final apk = File(
      '${root.path}/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk');
  if (apkBudget != null && apk.existsSync()) {
    _compare(
      findings,
      artifact: 'build/app/outputs/flutter-apk/app-arm64-v8a-release.apk',
      actual: apk.lengthSync(),
      unit: 'bytes',
      budget: apkBudget,
      key: 'apk_arm64_max_bytes',
    );
  }
  return findings;
}

const _check = 'C3-budgets';

/// Returns the usable budget under [key], or null with the reason recorded
/// in [findings]. A missing, mistyped, or non-positive budget never reaches
/// the comparison: a broken budget must fail loudly, not measure wrongly
/// (and a budget of 0 would make the overage percentage divide by zero).
int? _budget(
  Map<String, dynamic> json,
  String key,
  List<ConformanceFinding> findings,
) {
  if (!json.containsKey(key)) {
    findings.add(ConformanceFinding(
      _check,
      '$key missing from budgets.json — record the baseline+5% byte count',
    ));
    return null;
  }
  final value = json[key];
  if (value is! int) {
    findings.add(ConformanceFinding(
      _check,
      '$key must be an integer byte count, got '
      '${value == null ? 'null' : value.runtimeType} ($value)',
    ));
    return null;
  }
  if (value <= 0) {
    findings.add(ConformanceFinding(
      _check,
      '$key is $value — a non-positive budget silently disables the '
      'ratchet; record the real baseline+5% instead',
    ));
    return null;
  }
  return value;
}

void _compare(
  List<ConformanceFinding> findings, {
  required String artifact,
  required int actual,
  required String unit,
  required int budget,
  required String key,
}) {
  if (actual <= budget) return;
  final overPct = ((actual - budget) / budget * 100).toStringAsFixed(1);
  findings.add(ConformanceFinding(
    _check,
    '$artifact is over budget: $actual $unit vs a $key budget of '
    '$budget ($overPct% over) — claw the size back, or re-measure and '
    'ratchet the budget forward deliberately',
  ));
}
