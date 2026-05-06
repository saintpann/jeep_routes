/// Stop model representing a named stop along an E-Jeep route.
class Stop {
  final String stopId;
  final String name;
  final double latitude;
  final double longitude;
  final int sequence;

  const Stop({
    required this.stopId,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.sequence,
  });

  /// Deserialize from a JSON map.
  factory Stop.fromJson(Map<String, dynamic> json) {
    return Stop(
      stopId: json['stopId'] as String,
      name: json['name'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      sequence: json['sequence'] as int,
    );
  }

  /// Serialize to a JSON map.
  Map<String, dynamic> toJson() {
    return {
      'stopId': stopId,
      'name': name,
      'latitude': latitude,
      'longitude': longitude,
      'sequence': sequence,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Stop &&
        other.stopId == stopId &&
        other.name == name &&
        other.latitude == latitude &&
        other.longitude == longitude &&
        other.sequence == sequence;
  }

  @override
  int get hashCode =>
      Object.hash(stopId, name, latitude, longitude, sequence);

  @override
  String toString() {
    return 'Stop('
        'stopId: $stopId, '
        'name: $name, '
        'latitude: $latitude, '
        'longitude: $longitude, '
        'sequence: $sequence'
        ')';
  }
}

/// RouteGeoJSON model representing a named E-Jeep route with its geometry
/// and list of stops.
///
/// [geometry] is a list of [longitude, latitude] coordinate pairs following
/// the GeoJSON LineString convention (longitude first).
class RouteGeoJSON {
  final String routeId;
  final String routeName;

  /// Hex color string used for map rendering, e.g. "#2196F3".
  final String color;

  /// GeoJSON LineString coordinates as a list of [longitude, latitude] pairs.
  final List<List<double>> geometry;

  final List<Stop> stops;

  const RouteGeoJSON({
    required this.routeId,
    required this.routeName,
    required this.color,
    required this.geometry,
    required this.stops,
  });

  /// Deserialize from a JSON map.
  ///
  /// Expects [geometry] to be a list of coordinate arrays in
  /// [longitude, latitude] order (GeoJSON convention).
  factory RouteGeoJSON.fromJson(Map<String, dynamic> json) {
    final rawGeometry = json['geometry'] as List<dynamic>;
    final geometry = rawGeometry
        .map((coord) => (coord as List<dynamic>)
            .map((v) => (v as num).toDouble())
            .toList())
        .toList();

    final rawStops = json['stops'] as List<dynamic>;
    final stops = rawStops
        .map((s) => Stop.fromJson(s as Map<String, dynamic>))
        .toList();

    return RouteGeoJSON(
      routeId: json['routeId'] as String,
      routeName: json['routeName'] as String,
      color: json['color'] as String,
      geometry: geometry,
      stops: stops,
    );
  }

  /// Serialize to a JSON map.
  ///
  /// [geometry] is serialized as a list of [longitude, latitude] arrays
  /// following the GeoJSON convention.
  Map<String, dynamic> toJson() {
    return {
      'routeId': routeId,
      'routeName': routeName,
      'color': color,
      'geometry': geometry,
      'stops': stops.map((s) => s.toJson()).toList(),
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! RouteGeoJSON) return false;
    if (other.routeId != routeId ||
        other.routeName != routeName ||
        other.color != color) {
      return false;
    }
    if (other.geometry.length != geometry.length) return false;
    for (int i = 0; i < geometry.length; i++) {
      final a = geometry[i];
      final b = other.geometry[i];
      if (a.length != b.length) return false;
      for (int j = 0; j < a.length; j++) {
        if (a[j] != b[j]) return false;
      }
    }
    if (other.stops.length != stops.length) return false;
    for (int i = 0; i < stops.length; i++) {
      if (other.stops[i] != stops[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
        routeId,
        routeName,
        color,
        Object.hashAll(geometry.map((c) => Object.hashAll(c))),
        Object.hashAll(stops),
      );

  @override
  String toString() {
    return 'RouteGeoJSON('
        'routeId: $routeId, '
        'routeName: $routeName, '
        'color: $color, '
        'geometry: ${geometry.length} coords, '
        'stops: ${stops.length} stops'
        ')';
  }
}
