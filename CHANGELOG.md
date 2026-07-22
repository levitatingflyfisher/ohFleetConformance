# Changelog

## 0.2.0

The checks now scan code, not comments — a review pass found that most
source scans could be satisfied (or false-alarmed) by comments, strings,
or superstring names, including by this package's own conformant fixture.

- **C2 backup**: all sub-checks run on comment-stripped, string-blanked
  Dart source (new newline-preserving `strippedDartSource`); the
  serializer must be a real one-line class declaration
  (`BackupSerializerRegistry` and newline-spanning matches no longer
  count); `runStartupMaintenance` must be a call site.
- **C1 style**: pubspec dependency walk skips `#` comment lines and
  examines every occurrence of the key (`dependency_overrides` included);
  the canonical path must *end* at `ohStyle/openhearth_design` on a
  segment boundary (`evil/ohStyle/openhearth_design-fork` shapes fail);
  the retyped-token scan ignores comments/strings, and the hex pattern
  gained a right boundary so 16-digit masks no longer half-match.
- **C4 permissions**: `<!-- -->` comments are stripped before the
  uses-permission scan; single-quoted `android:name` is recognized.
- **C6 harness**: the flutter-version scan is comment-aware; a
  `${{ ... }}` value is reported as its own expression-pin finding; a
  workflow using subosito/flutter-action with no `flutter-version` at all
  is now a finding.
- **Runner**: `runFleetConformance` evaluates all checks once per suite
  (lazy shared memo) instead of once per test, and a check that throws
  becomes a finding on that check alone instead of failing all five tests.
- **Canonical flutter_test_config template**: the FontManifest family loop
  guards each family individually — one family's failure logs and
  continues instead of aborting the families after it (MaterialIcons loads
  first, so its failure used to silently kill Lora/Nunito). Apps re-sync
  their copies from this constant.

## 0.1.0

Initial release: the fleet-standardization campaign's enforcement layer.
C1 style (canonical design package, no vendored forks, no retyped token
literals), C2 backup (retention-spec conformance incl. honest merge-restore
copy), C3 size budgets (gzip JS + arm64 APK ratchet), C4 Android permission
allowlists, C5 320dp×3.0 accessibility sweep helper, C6 harness canon
(flutter_test_config / analysis_options / CI pin), all behind one
`runFleetConformance(FleetAppConfig)` call per app.
