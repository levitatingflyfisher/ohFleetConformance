import 'package:flutter_test/flutter_test.dart';
import 'package:oh_fleet_conformance/src/dart_source.dart';

void main() {
  test('removes line comments but preserves line count', () {
    const source = 'final a = 1; // BackupEnvelope.unwrap\n'
        '// runStartupMaintenance();\n'
        'final b = 2;\n';
    final stripped = strippedDartSource(source);
    expect(stripped, isNot(contains('BackupEnvelope')));
    expect(stripped, isNot(contains('runStartupMaintenance')));
    expect(stripped, contains('final a = 1;'));
    expect(stripped, contains('final b = 2;'));
    expect('\n'.allMatches(stripped).length, '\n'.allMatches(source).length);
  });

  test('removes block comments, preserving interior newlines', () {
    const source = 'final a = 1;\n'
        '/* line one\n'
        '   BackupEnvelope.wrap()\n'
        '*/\n'
        'final b = 2;\n';
    final stripped = strippedDartSource(source);
    expect(stripped, isNot(contains('BackupEnvelope')));
    expect('\n'.allMatches(stripped).length, '\n'.allMatches(source).length);
    // Line numbers survive: 'final b' is still on line 5.
    expect(stripped.split('\n')[4], contains('final b = 2;'));
  });

  test('handles nested block comments (Dart nests them)', () {
    const source = '/* outer /* inner */ still comment */ final a = 1;\n';
    final stripped = strippedDartSource(source);
    expect(stripped, isNot(contains('inner')));
    expect(stripped, isNot(contains('still comment')));
    expect(stripped, contains('final a = 1;'));
  });

  test('blanks string contents but keeps the quotes', () {
    const source = "final s = 'runStartupMaintenance()';\n"
        'final d = "BackupEnvelope.unwrap";\n';
    final stripped = strippedDartSource(source);
    expect(stripped, isNot(contains('runStartupMaintenance')));
    expect(stripped, isNot(contains('BackupEnvelope')));
    expect(stripped, contains("final s = '';"));
    expect(stripped, contains('final d = "";'));
  });

  test('blanks triple-quoted strings, preserving interior newlines', () {
    const source = "final s = '''\nBackupEnvelope\nline\n''';\nfinal b = 2;\n";
    final stripped = strippedDartSource(source);
    expect(stripped, isNot(contains('BackupEnvelope')));
    expect('\n'.allMatches(stripped).length, '\n'.allMatches(source).length);
  });

  test('an escaped quote does not end a string', () {
    const source = "final s = 'it\\'s runStartupMaintenance';\nfinal b = 2;\n";
    final stripped = strippedDartSource(source);
    expect(stripped, isNot(contains('runStartupMaintenance')));
    expect(stripped, contains('final b = 2;'));
  });

  test('raw strings treat backslash literally', () {
    // In r'...\' the backslash does NOT escape the quote; the string ends
    // at the quote and the tail is real code.
    const source = "final s = r'path\\';\nBackupEnvelope.wrap();\n";
    final stripped = strippedDartSource(source);
    expect(stripped, contains('BackupEnvelope.wrap();'));
  });

  test('a quote inside a comment does not open a string', () {
    const source = "// don't strip the next line\nfinal a = 1;\n";
    expect(strippedDartSource(source), contains('final a = 1;'));
  });

  test('// inside a string is not a comment', () {
    const source = "final url = 'https://example.com'; final a = 1;\n";
    expect(strippedDartSource(source), contains('final a = 1;'));
  });

  test('code outside comments and strings is untouched', () {
    const source = 'void main() {\n  runStartupMaintenance();\n}\n';
    expect(strippedDartSource(source), source);
  });
}
