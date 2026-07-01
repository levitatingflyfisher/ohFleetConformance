import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
// Imported via src until the orchestrator wires the barrel export.
import 'package:oh_fleet_conformance/src/checks/budgets.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('ohfc_budget_');
  });

  tearDown(() {
    root.deleteSync(recursive: true);
  });

  void writeBudgets(String json) {
    File('${root.path}/budgets.json').writeAsStringSync(json);
  }

  File writeMainDartJs(List<int> bytes) {
    final file = File('${root.path}/build/web/main.dart.js');
    file.createSync(recursive: true);
    file.writeAsBytesSync(bytes);
    return file;
  }

  File writeApk(int lengthBytes) {
    final file = File(
        '${root.path}/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk');
    file.createSync(recursive: true);
    // Content is irrelevant to the check — only the plain file length is.
    file.writeAsBytesSync(List.filled(lengthBytes, 0x42));
    return file;
  }

  // 100KB of a single repeated byte: gzips to a few hundred bytes, so the
  // raw and compressed sizes are far enough apart to tell which one the
  // check actually measured.
  final repetitive = List<int>.filled(100 * 1024, 0x61);

  test('recorded budgets with under-budget artifacts yield no findings', () {
    writeBudgets(jsonEncode({
      'main_dart_js_gz_max_bytes': 10 * 1024,
      'apk_arm64_max_bytes': 4096,
    }));
    writeMainDartJs(repetitive); // gzips to well under 10KB
    writeApk(2048);
    expect(checkSizeBudgets(root: root), isEmpty);
  });

  test('missing budgets.json is a finding telling the maintainer to record '
      'baselines', () {
    final findings = checkSizeBudgets(root: root);
    expect(findings, hasLength(1));
    expect(findings.single.message, contains('budgets.json'));
    expect(findings.single.message, contains('baseline'));
  });

  test('malformed JSON is a finding carrying the parse problem, not a throw',
      () {
    writeBudgets('{"main_dart_js_gz_max_bytes": }');
    final findings = checkSizeBudgets(root: root);
    expect(findings, hasLength(1));
    expect(findings.single.message, contains('budgets.json'));
    // The maintainer should see WHERE the JSON broke, not just that it did.
    expect(findings.single.message, contains('Unexpected character'));
  });

  test('valid JSON that is not an object is a finding, not a throw', () {
    writeBudgets('[1, 2]');
    final findings = checkSizeBudgets(root: root);
    expect(findings, hasLength(1));
    expect(findings.single.message, contains('budgets.json'));
  });

  test('a missing key is a finding naming the key', () {
    writeBudgets(jsonEncode({'main_dart_js_gz_max_bytes': 1024}));
    final findings = checkSizeBudgets(root: root);
    expect(findings, hasLength(1));
    expect(findings.single.message, contains('apk_arm64_max_bytes'));
  });

  test('a wrong-typed key is a finding naming the key', () {
    writeBudgets(jsonEncode({
      'main_dart_js_gz_max_bytes': '1048576', // a string, not an int
      'apk_arm64_max_bytes': 4096,
    }));
    final findings = checkSizeBudgets(root: root);
    expect(findings, hasLength(1));
    expect(findings.single.message, contains('main_dart_js_gz_max_bytes'));
  });

  test('both keys missing report independently', () {
    writeBudgets('{}');
    final findings = checkSizeBudgets(root: root);
    expect(findings, hasLength(2));
    expect(findings.map((f) => f.message).join(),
        allOf(contains('main_dart_js_gz_max_bytes'),
            contains('apk_arm64_max_bytes')));
  });

  test('extra keys are tolerated silently', () {
    // Apps may record measurement notes alongside the two budget keys.
    writeBudgets(jsonEncode({
      'main_dart_js_gz_max_bytes': 1024,
      'apk_arm64_max_bytes': 4096,
      'measured_on': '2026-07-17',
      'notes': 'baseline+5% from the v1.2 deploy build',
    }));
    expect(checkSizeBudgets(root: root), isEmpty);
  });

  test('absent artifacts pass — a plain flutter test run without a build '
      'must not fail', () {
    writeBudgets(jsonEncode({
      'main_dart_js_gz_max_bytes': 1024,
      'apk_arm64_max_bytes': 4096,
    }));
    expect(checkSizeBudgets(root: root), isEmpty);
  });

  test('main.dart.js is measured gzipped: raw size over budget alone is not '
      'a finding', () {
    final gzLen = GZipCodec().encode(repetitive).length;
    // Budget sits between the compressed and raw sizes; only a raw-size
    // comparison would flag this.
    writeBudgets(jsonEncode({
      'main_dart_js_gz_max_bytes': 10 * 1024,
      'apk_arm64_max_bytes': 4096,
    }));
    writeMainDartJs(repetitive);
    expect(gzLen, lessThan(10 * 1024));
    expect(repetitive.length, greaterThan(10 * 1024));
    expect(checkSizeBudgets(root: root), isEmpty);
  });

  test('main.dart.js over gzip budget reports compressed size, budget, and '
      'overage percentage', () {
    final gzLen = GZipCodec().encode(repetitive).length;
    const budget = 64; // below any gzip of a 100KB payload
    writeBudgets(jsonEncode({
      'main_dart_js_gz_max_bytes': budget,
      'apk_arm64_max_bytes': 4096,
    }));
    writeMainDartJs(repetitive);
    final findings = checkSizeBudgets(root: root);
    expect(findings, hasLength(1));
    final message = findings.single.message;
    expect(message, contains('main.dart.js'));
    expect(message, contains('$gzLen')); // the gzipped size…
    expect(message, isNot(contains('${repetitive.length}'))); // …not the raw
    expect(message, contains('$budget'));
    expect(message, contains('%'));
  });

  test('APK over budget reports plain file length, budget, and overage '
      'percentage', () {
    writeBudgets(jsonEncode({
      'main_dart_js_gz_max_bytes': 1024,
      'apk_arm64_max_bytes': 1024,
    }));
    writeApk(2048);
    final findings = checkSizeBudgets(root: root);
    expect(findings, hasLength(1));
    final message = findings.single.message;
    expect(message, contains('app-arm64-v8a-release.apk'));
    expect(message, contains('2048'));
    expect(message, contains('1024'));
    expect(message, contains('100.0%'));
  });

  test('zero or negative budgets are findings — a zeroed budget silently '
      'disables the ratchet', () {
    writeBudgets(jsonEncode({
      'main_dart_js_gz_max_bytes': 0,
      'apk_arm64_max_bytes': -1,
    }));
    final findings = checkSizeBudgets(root: root);
    expect(findings, hasLength(2));
    expect(findings.map((f) => f.message).join(),
        allOf(contains('main_dart_js_gz_max_bytes'),
            contains('apk_arm64_max_bytes')));
  });

  test('check id is C3-budgets on every finding', () {
    final findings = checkSizeBudgets(root: root); // missing budgets.json
    expect(findings.single.check, 'C3-budgets');
  });
}
