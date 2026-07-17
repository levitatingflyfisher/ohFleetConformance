# Changelog

## 0.1.0

Initial release: the fleet-standardization campaign's enforcement layer.
C1 style (canonical design package, no vendored forks, no retyped token
literals), C2 backup (retention-spec conformance incl. honest merge-restore
copy), C3 size budgets (gzip JS + arm64 APK ratchet), C4 Android permission
allowlists, C5 320dp×3.0 accessibility sweep helper, C6 harness canon
(flutter_test_config / analysis_options / CI pin), all behind one
`runFleetConformance(FleetAppConfig)` call per app.
