import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/models.dart';

/// Service that loads and caches E-Jeep route data from the bundled
/// `assets/routes.geojson` asset.
///
/// Routes are parsed once and held in memory. Call [clearCache] to force a
/// reload on the next [loadRoutes] call.
class RouteDataService {
  List<RouteGeoJSON>? _cachedRoutes;

  // ---------------------------------------------------------------------------
  // loadRoutes
  // ---------------------------------------------------------------------------

  /// Loads all routes from the bundled GeoJSON asset.
  ///
  /// Returns the cached list on subsequent calls without re-parsing.
  /// The GeoJSON must be a FeatureCollection where each Feature's
  /// `properties` contains `routeId`, `routeName`, `color`, and `stops`,
  /// and `geometry.coordinates` is a GeoJSON LineString.
  Future<List<RouteGeoJSON>> loadRoutes() async {
    if (_cachedRoutes != null) return _cachedRoutes!;

    final raw = await rootBundle.loadString('assets/routes.geojson');
    final json = jsonDecode(raw) as Map<String, dynamic>;

    final features = json['features'] as List<dynamic>;
    final routes = features.map((feature) {
      final f = feature as Map<String, dynamic>;
      final props = f['properties'] as Map<String, dynamic>;
      final geom = f['geometry'] as Map<String, dynamic>;

      // Parse LineString coordinates [[lng, lat], ...]
      final rawCoords = geom['coordinates'] as List<dynamic>;
      final geometry = rawCoords
          .map((c) => (c as List<dynamic>)
              .map((v) => (v as num).toDouble())
              .toList())
          .toList()
          .cast<List<double>>();

      // Parse stops from properties
      final rawStops = props['stops'] as List<dynamic>;
      final stops = rawStops
          .map((s) => Stop.fromJson(s as Map<String, dynamic>))
          .toList();

      return RouteGeoJSON(
        routeId: props['routeId'] as String,
        routeName: props['routeName'] as String,
        color: props['color'] as String,
        geometry: geometry,
        stops: stops,
      );
    }).toList();

    _cachedRoutes = routes;
    return _cachedRoutes!;
  }

  // ---------------------------------------------------------------------------
  // getRouteById
  // ---------------------------------------------------------------------------

  /// Returns the [RouteGeoJSON] with the given [routeId], or `null` if not
  /// found or the cache has not been populated yet.
  RouteGeoJSON? getRouteById(String routeId) {
    if (_cachedRoutes == null) return null;
    try {
      return _cachedRoutes!.firstWhere((r) => r.routeId == routeId);
    } on StateError {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // getStopsForRoute
  // ---------------------------------------------------------------------------

  /// Returns the list of [Stop]s for the given [routeId].
  ///
  /// Returns an empty list if the route is not found or the cache is empty.
  List<Stop> getStopsForRoute(String routeId) {
    return getRouteById(routeId)?.stops ?? [];
  }

  // ---------------------------------------------------------------------------
  // clearCache
  // ---------------------------------------------------------------------------

  /// Clears the in-memory route cache. The next call to [loadRoutes] will
  /// re-parse the bundled asset.
  void clearCache() {
    _cachedRoutes = null;
  }
}
