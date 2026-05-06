import 'dart:async';

import 'package:firebase_database/firebase_database.dart';

/// Data class representing a commuter-dropped pin on the map.
class CommutterPin {
  final String pinId;
  final double latitude;
  final double longitude;
  final String type;
  final int timestamp;

  const CommutterPin({
    required this.pinId,
    required this.latitude,
    required this.longitude,
    required this.type,
    required this.timestamp,
  });

  factory CommutterPin.fromJson(String pinId, Map<dynamic, dynamic> json) {
    return CommutterPin(
      pinId: pinId,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      type: json['type'] as String,
      timestamp: (json['timestamp'] as num).toInt(),
    );
  }
}

/// Allowed pin types for [PinService.dropPin].
const Set<String> _kAllowedPinTypes = {'sos', 'blocked', 'long_line'};

/// Duration in milliseconds after which a pin is considered expired (1 hour).
const int _kPinExpiryMs = 3600000;

/// Service responsible for writing commuter context pins to `/pins` in Firebase
/// Realtime Database and exposing a filtered stream of recent pins.
class PinService {
  final StreamController<List<CommutterPin>> _controller =
      StreamController<List<CommutterPin>>.broadcast();

  StreamSubscription<DatabaseEvent>? _rtdbSubscription;

  PinService() {
    _init();
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Stream of recent pins (age ≤ 1 hour) from `/pins` in RTDB.
  ///
  /// Emits a new list whenever the underlying RTDB data changes.
  Stream<List<CommutterPin>> get pinsStream => _controller.stream;

  /// Writes a new pin to `/pins` in RTDB.
  ///
  /// [latitude] must be in the range [-90, 90].
  /// [longitude] must be in the range [-180, 180].
  /// [type] must be one of `"sos"`, `"blocked"`, or `"long_line"`.
  ///
  /// Throws [ArgumentError] if any input is invalid.
  Future<void> dropPin(
    double latitude,
    double longitude,
    String type,
  ) async {
    if (latitude < -90 || latitude > 90) {
      throw ArgumentError.value(
        latitude,
        'latitude',
        'Latitude must be in the range [-90, 90].',
      );
    }
    if (longitude < -180 || longitude > 180) {
      throw ArgumentError.value(
        longitude,
        'longitude',
        'Longitude must be in the range [-180, 180].',
      );
    }
    if (!_kAllowedPinTypes.contains(type)) {
      throw ArgumentError.value(
        type,
        'type',
        'Pin type must be one of: ${_kAllowedPinTypes.join(', ')}.',
      );
    }

    await FirebaseDatabase.instance.ref('pins').push().set({
      'latitude': latitude,
      'longitude': longitude,
      'type': type,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Cancels the RTDB subscription and closes the stream controller.
  void dispose() {
    _rtdbSubscription?.cancel();
    _rtdbSubscription = null;
    _controller.close();
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  void _init() {
    _rtdbSubscription = FirebaseDatabase.instance
        .ref('pins')
        .onValue
        .listen(_onDatabaseEvent, onError: (_) {
      // Silently ignore RTDB errors; the stream will resume on reconnect.
    });
  }

  void _onDatabaseEvent(DatabaseEvent event) {
    final snapshot = event.snapshot;
    final raw = snapshot.value;

    if (raw == null) {
      _controller.add([]);
      return;
    }

    final List<CommutterPin> pins = [];
    final now = DateTime.now().millisecondsSinceEpoch;

    if (raw is Map) {
      for (final entry in raw.entries) {
        try {
          final pinMap = Map<dynamic, dynamic>.from(entry.value as Map);
          final pin = CommutterPin.fromJson(entry.key as String, pinMap);
          if ((now - pin.timestamp) <= _kPinExpiryMs) {
            pins.add(pin);
          }
        } catch (_) {
          // Skip malformed entries.
        }
      }
    }

    _controller.add(pins);
  }
}
