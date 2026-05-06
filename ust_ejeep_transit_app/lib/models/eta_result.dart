/// Confidence level for an ETA estimate.
///
/// - [high]: vehicle speed > 0 and position age < 10 s
/// - [medium]: speed is 0 but position is recent (< 10 s)
/// - [low]: position age is between 10 s and the stale threshold
enum ETAConfidence {
  high,
  medium,
  low,
}

/// Sealed class representing the result of an ETA calculation for a stop.
///
/// Use pattern matching to handle both outcomes:
/// ```dart
/// switch (result) {
///   case ETAAvailable(:final estimatedArrivalSec):
///     // show ETA badge
///   case ETAUnavailable(:final reason):
///     // show unavailable state
/// }
/// ```
sealed class ETAResult {
  const ETAResult();
}

/// ETA is available — carries all fields needed to display an arrival estimate.
final class ETAAvailable extends ETAResult {
  /// Firebase UID of the vehicle this ETA applies to.
  final String vehicleId;

  /// Target stop identifier.
  final String stopId;

  final String routeId;

  /// Estimated seconds until the vehicle arrives at [stopId]. Always >= 0.
  final int estimatedArrivalSec;

  /// Remaining distance along the route in metres.
  final double distanceRemainingM;

  final ETAConfidence confidence;

  /// Unix epoch milliseconds when this ETA was computed.
  final int computedAt;

  const ETAAvailable({
    required this.vehicleId,
    required this.stopId,
    required this.routeId,
    required this.estimatedArrivalSec,
    required this.distanceRemainingM,
    required this.confidence,
    required this.computedAt,
  }) : assert(estimatedArrivalSec >= 0,
            'estimatedArrivalSec must be >= 0');

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ETAAvailable &&
        other.vehicleId == vehicleId &&
        other.stopId == stopId &&
        other.routeId == routeId &&
        other.estimatedArrivalSec == estimatedArrivalSec &&
        other.distanceRemainingM == distanceRemainingM &&
        other.confidence == confidence &&
        other.computedAt == computedAt;
  }

  @override
  int get hashCode => Object.hash(
        vehicleId,
        stopId,
        routeId,
        estimatedArrivalSec,
        distanceRemainingM,
        confidence,
        computedAt,
      );

  @override
  String toString() {
    return 'ETAAvailable('
        'vehicleId: $vehicleId, '
        'stopId: $stopId, '
        'routeId: $routeId, '
        'estimatedArrivalSec: $estimatedArrivalSec, '
        'distanceRemainingM: $distanceRemainingM, '
        'confidence: ${confidence.name}, '
        'computedAt: $computedAt'
        ')';
  }
}

/// ETA is unavailable — carries a machine-readable [reason] string.
///
/// Known reason codes:
/// - `"VEHICLE_INACTIVE"` — vehicle is not currently streaming
/// - `"STALE_POSITION"` — last known position exceeds the staleness threshold
/// - `"STOP_PASSED"` — vehicle has already passed the requested stop
/// - `"UNKNOWN_ROUTE"` — [routeId] does not match any known route
/// - `"UNKNOWN_STOP"` — [stopId] does not exist on the given route
/// - `"SERVICE_ERROR"` — unexpected error in the ETA calculation service
final class ETAUnavailable extends ETAResult {
  final String reason;

  const ETAUnavailable({required this.reason});

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ETAUnavailable && other.reason == reason;
  }

  @override
  int get hashCode => reason.hashCode;

  @override
  String toString() => 'ETAUnavailable(reason: $reason)';
}
