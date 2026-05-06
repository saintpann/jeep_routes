import 'package:cloud_functions/cloud_functions.dart';

import '../models/models.dart';

/// Client-side service that calls the `calculateETA` Firebase Cloud Function
/// and caches results per stop for up to 10 seconds.
class ETAService {
  final Map<String, _CachedETA> _cache = {};

  /// Calls the `calculateETA` Cloud Function and returns an [ETAResult].
  ///
  /// Results are cached per [stopId] for 10 seconds to avoid redundant calls.
  /// Returns [ETAUnavailable] with reason `"SERVICE_ERROR"` on any failure.
  Future<ETAResult> calculateETA(
    String vehicleId,
    String stopId,
    String routeId,
  ) async {
    // Cache key includes vehicleId so different vehicles at the same stop
    // don't share a stale result.
    final cacheKey = '$vehicleId:$stopId';

    // Check cache (10 second TTL).
    final cached = _cache[cacheKey];
    if (cached != null &&
        DateTime.now().millisecondsSinceEpoch - cached.timestamp < 10000) {
      return cached.result;
    }

    try {
      final callable =
          FirebaseFunctions.instance.httpsCallable('calculateETA');
      final result = await callable.call({
        'vehicleId': vehicleId,
        'stopId': stopId,
        'routeId': routeId,
      });

      // The cloud_functions plugin returns data as Map<Object?, Object?>.
      // Cast it safely to Map<String, dynamic> before accessing fields.
      final raw = result.data;
      final data = (raw is Map)
          ? raw.map((k, v) => MapEntry(k.toString(), v))
          : <String, dynamic>{};

      ETAResult etaResult;

      if (data['status'] == 'available') {
        etaResult = ETAAvailable(
          vehicleId: vehicleId,
          stopId: stopId,
          routeId: routeId,
          estimatedArrivalSec:
              (data['estimatedArrivalSec'] as num).toInt(),
          distanceRemainingM:
              (data['distanceRemainingM'] as num).toDouble(),
          confidence: ETAConfidence.values
              .byName(data['confidence'] as String),
          computedAt: (data['computedAt'] as num).toInt(),
        );
      } else {
        etaResult = ETAUnavailable(
          reason: data['reason'] as String? ?? 'SERVICE_ERROR',
        );
      }

      _cache[cacheKey] =
          _CachedETA(etaResult, DateTime.now().millisecondsSinceEpoch);
      return etaResult;
    } on FirebaseFunctionsException catch (e) {
      return ETAUnavailable(reason: e.code);
    } catch (_) {
      return const ETAUnavailable(reason: 'SERVICE_ERROR');
    }
  }
}

class _CachedETA {
  final ETAResult result;
  final int timestamp;

  const _CachedETA(this.result, this.timestamp);
}
