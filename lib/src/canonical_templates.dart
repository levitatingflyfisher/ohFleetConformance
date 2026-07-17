// The harness canon, embedded verbatim. These constants are the single
// source of truth the fleet syncs TO (checkHarnessCanon enforces them):
// update a constant first, then sync the apps — never the other way round.

/// The fleet's `test/flutter_test_config.dart` — the FontManifest-aware
/// variant, byte-identical across Trellis/Reckon at embed time (md5
/// bbe6186ad7eb666ab9bb6188eb15ada0). Divergence here is why one app's
/// goldens load real fonts while another's render placeholder boxes: this
/// config decides what every golden in the app sees.
const String canonicalFlutterTestConfig = r'''
// Copy to: <flutter_project>/test/flutter_test_config.dart
// (auto-loaded by `flutter test` for every test under test/)
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Loads real fonts so golden PNGs show readable text instead of the
/// placeholder boxes Flutter renders by default:
///  1. the app's OWN bundled fonts (e.g. openhearth_design's Lora / Nunito)
///     from its asset manifest — so goldens show the real design-system type;
///  2. the SDK Roboto + Material Icons as the default-family fallback.
/// Both are best-effort: if fonts can't be found, tests still run (text just
/// falls back to boxes).
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await _loadAppBundledFonts();
  await _loadSdkFonts();
  return testMain();
}

/// Loads every font the app declares in its pubspec (via FontManifest.json),
/// so goldens render the app's real bundled type. No-op if the app bundles no
/// fonts. This is what makes design-system fonts (Lora/Nunito/JetBrains Mono)
/// render instead of boxes.
Future<void> _loadAppBundledFonts() async {
  try {
    final String manifest = await rootBundle.loadString('FontManifest.json');
    final List<dynamic> families = json.decode(manifest) as List<dynamic>;
    for (final dynamic entry in families) {
      final Map<String, dynamic> e = entry as Map<String, dynamic>;
      final String? family = e['family'] as String?;
      final List<dynamic>? fonts = e['fonts'] as List<dynamic>?;
      if (family == null || fonts == null) continue;
      final FontLoader loader = FontLoader(family);
      for (final dynamic f in fonts) {
        final String? asset = (f as Map<String, dynamic>)['asset'] as String?;
        if (asset != null) loader.addFont(rootBundle.load(asset));
      }
      await loader.load();
    }
  } catch (_) {
    // No FontManifest (app bundles no fonts) — fine.
  }
}

/// Loads the active Flutter SDK's Roboto + Material Icons as the default family
/// (covers apps that use the Material default type, and Material icons).
Future<void> _loadSdkFonts() async {
  final Directory? fontsDir = _materialFontsDir();
  if (fontsDir == null) return;

  ByteData? read(String name) {
    final File f = File('${fontsDir.path}/$name');
    if (!f.existsSync()) return null;
    return ByteData.view(Uint8List.fromList(f.readAsBytesSync()).buffer);
  }

  Future<void> load(String family, List<String> files) async {
    final FontLoader loader = FontLoader(family);
    bool any = false;
    for (final String file in files) {
      final ByteData? data = read(file);
      if (data != null) {
        loader.addFont(Future<ByteData>.value(data));
        any = true;
      }
    }
    if (any) await loader.load();
  }

  await load('Roboto', <String>[
    'Roboto-Regular.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
    'Roboto-Light.ttf',
  ]);
  await load('MaterialIcons', <String>['MaterialIcons-Regular.otf']);
}

/// Resolves the active Flutter SDK's `material_fonts` cache directory.
Directory? _materialFontsDir() {
  final List<String> candidates = <String>[];
  final String? root = Platform.environment['FLUTTER_ROOT'];
  if (root != null && root.isNotEmpty) {
    candidates.add('$root/bin/cache/artifacts/material_fonts');
  }
  try {
    final Directory cache =
        File(Platform.resolvedExecutable).parent.parent.parent;
    candidates.add('${cache.path}/artifacts/material_fonts');
  } catch (_) {}
  for (final String c in candidates) {
    final Directory d = Directory(c);
    if (d.existsSync()) return d;
  }
  return null;
}
''';

/// The stock `analysis_options.yaml` shipped by `flutter create`, carried
/// byte-identically by the stock apps (verified Sundial == Furrow, md5
/// 66d03d7647c8e438164feaf5b922d44a). Reckon/PT/StillLife carry
/// deliberately-tighter configs — those record a per-app override
/// (checkHarnessCanon's analysisOptionsOverrideRecorded) instead of
/// loosening this template.
const String canonicalAnalysisOptions = r'''
# This file configures the analyzer, which statically analyzes Dart code to
# check for errors, warnings, and lints.
#
# The issues identified by the analyzer are surfaced in the UI of Dart-enabled
# IDEs (https://dart.dev/tools#ides-and-editors). The analyzer can also be
# invoked from the command line by running `flutter analyze`.

# The following line activates a set of recommended lints for Flutter apps,
# packages, and plugins designed to encourage good coding practices.
include: package:flutter_lints/flutter.yaml

linter:
  # The lint rules applied to this project can be customized in the
  # section below to disable rules from the `package:flutter_lints/flutter.yaml`
  # included above or to enable additional rules. A list of all available lints
  # and their documentation is published at https://dart.dev/lints.
  #
  # Instead of disabling a lint rule for the entire project in the
  # section below, it can also be suppressed for a single line of code
  # or a specific dart file by using the `// ignore: name_of_lint` and
  # `// ignore_for_file: name_of_lint` syntax on the line or in the file
  # producing the lint.
  rules:
    # avoid_print: false  # Uncomment to disable the `avoid_print` rule
    # prefer_single_quotes: true  # Uncomment to enable the `prefer_single_quotes` rule

# Additional information about this file can be found at
# https://dart.dev/guides/language/analysis-options
''';
