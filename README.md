# oh_fleet_conformance

The OpenHearth fleet's standards, as tests that can fail — never as
documents that drift.

An app adopts the whole suite with one file:

```dart
// test/fleet_conformance_test.dart
import 'package:oh_fleet_conformance/oh_fleet_conformance.dart';

void main() => runFleetConformance(const FleetAppConfig(
      appId: 'sundial',
      styleTier: StyleTier.tokens,
      androidPermissions: {
        'android.permission.POST_NOTIFICATIONS',
        'android.permission.VIBRATE',
      },
    ));
```

## The checks

| Check | Enforces |
|---|---|
| C1 style | The design grammar has ONE source of truth: canonical `openhearth_design` consumed by sibling path (no vendored forks — a fork's hues silently diverged once already), and no retyped token hex literals in `lib/`. |
| C2 backup | `BACKUP_RETENTION_SPEC.md`'s enforcement layer: sanctuary_backup_ui ≥ 0.2.0 actually relocked, serializer on the shared `BackupEnvelope` + `PreviewableBackupSerializer`, merge-restore apps override the destructive confirm copy, the startup maintenance hook exists. |
| C3 budgets | Measure–budget–ratchet: `budgets.json` baselines vs on-disk artifacts (gzipped `main.dart.js`, arm64 APK). Artifacts absent → skip; budgets absent or zeroed → fail. |
| C4 permissions | The app's exact `<uses-permission>` surface, both directions — the no-INTERNET and zero-permission claims are tests, not promises. |
| C5 a11y | `runA11ySweep` — the 320dp × 3.0 text-scale sweep template, including opened dialogs (where the fleet's overflow bugs actually live). |
| C6 harness | Canonical `flutter_test_config.dart` (the FontManifest-aware variant — divergence means goldens render different fonts per app), canonical `analysis_options.yaml` (recorded tighter overrides allowed), CI exists and pins the real fleet Flutter version. |

Every deliberate divergence is a recorded field on `FleetAppConfig` — one
place to read an app's posture, nothing scattered.

Findings are returned, not thrown: one failing check reports *every*
violation in its area with file/line specifics.
