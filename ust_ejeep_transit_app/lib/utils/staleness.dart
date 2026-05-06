/// Threshold in milliseconds after which a vehicle position is considered stale.
const int kStaleThresholdMs = 30000;

/// Returns `true` if [timestamp] (milliseconds since epoch) is within the
/// last [kStaleThresholdMs] milliseconds relative to the current wall clock.
///
/// A vehicle whose last-known position is older than 30 seconds is considered
/// stale and should be hidden from the map.
bool isRecent(int timestamp) {
  return DateTime.now().millisecondsSinceEpoch - timestamp <= kStaleThresholdMs;
}
