/// VehicleState model representing a live E-Jeep vehicle position payload
/// stored in Firebase Realtime Database under /vehicles/{driverUID}.
class VehicleState {
  final String vehicleId;
  final String driverName;
  final String routeId;
  final double latitude;
  final double longitude;
  final double accuracy;
  final double heading;
  final double speed;
  final int timestamp;
  final bool isActive;

  const VehicleState({
    required this.vehicleId,
    required this.driverName,
    required this.routeId,
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.heading,
    required this.speed,
    required this.timestamp,
    required this.isActive,
  });

  /// Deserialize from a Firebase RTDB JSON map.
  factory VehicleState.fromJson(Map<String, dynamic> json) {
    return VehicleState(
      vehicleId: json['vehicleId'] as String,
      driverName: json['driverName'] as String,
      routeId: json['routeId'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      accuracy: (json['accuracy'] as num).toDouble(),
      heading: (json['heading'] as num).toDouble(),
      speed: (json['speed'] as num).toDouble(),
      // Firebase RTDB may return large integers as doubles; use (num).toInt()
      // to handle both int and double representations safely.
      timestamp: (json['timestamp'] as num).toInt(),
      isActive: json['isActive'] as bool,
    );
  }

  /// Serialize to a Firebase RTDB-compatible JSON map.
  Map<String, dynamic> toJson() {
    return {
      'vehicleId': vehicleId,
      'driverName': driverName,
      'routeId': routeId,
      'latitude': latitude,
      'longitude': longitude,
      'accuracy': accuracy,
      'heading': heading,
      'speed': speed,
      'timestamp': timestamp,
      'isActive': isActive,
    };
  }

  /// Returns a copy of this [VehicleState] with the given fields replaced.
  VehicleState copyWith({
    String? vehicleId,
    String? driverName,
    String? routeId,
    double? latitude,
    double? longitude,
    double? accuracy,
    double? heading,
    double? speed,
    int? timestamp,
    bool? isActive,
  }) {
    return VehicleState(
      vehicleId: vehicleId ?? this.vehicleId,
      driverName: driverName ?? this.driverName,
      routeId: routeId ?? this.routeId,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      accuracy: accuracy ?? this.accuracy,
      heading: heading ?? this.heading,
      speed: speed ?? this.speed,
      timestamp: timestamp ?? this.timestamp,
      isActive: isActive ?? this.isActive,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is VehicleState &&
        other.vehicleId == vehicleId &&
        other.driverName == driverName &&
        other.routeId == routeId &&
        other.latitude == latitude &&
        other.longitude == longitude &&
        other.accuracy == accuracy &&
        other.heading == heading &&
        other.speed == speed &&
        other.timestamp == timestamp &&
        other.isActive == isActive;
  }

  @override
  int get hashCode {
    return Object.hash(
      vehicleId,
      driverName,
      routeId,
      latitude,
      longitude,
      accuracy,
      heading,
      speed,
      timestamp,
      isActive,
    );
  }

  @override
  String toString() {
    return 'VehicleState('
        'vehicleId: $vehicleId, '
        'driverName: $driverName, '
        'routeId: $routeId, '
        'latitude: $latitude, '
        'longitude: $longitude, '
        'accuracy: $accuracy, '
        'heading: $heading, '
        'speed: $speed, '
        'timestamp: $timestamp, '
        'isActive: $isActive'
        ')';
  }
}
