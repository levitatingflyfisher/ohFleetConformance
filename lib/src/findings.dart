/// A single conformance violation.
///
/// Checks return a list of these (empty = conformant) rather than throwing,
/// so one test can report every violation in an app at once instead of
/// stopping at the first.
class ConformanceFinding {
  /// Which check produced this (e.g. 'C4-permissions').
  final String check;

  /// Human-readable violation, specific enough to act on without re-running.
  final String message;

  const ConformanceFinding(this.check, this.message);

  @override
  String toString() => '[$check] $message';
}
