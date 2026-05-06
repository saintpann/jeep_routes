import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/models.dart';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/// Maximum acceptable GPS accuracy in metres. Readings above this are skipped.
const double kMaxAccuracyThreshold = 50.0;

/// Normal poll interval in seconds (vehicle moving).
const int kPollIntervalSeconds = 3;

/// Slow poll interval in seconds (vehicle stationary / very slow).
const int kSlowPollIntervalSeconds = 5;

/// Speed threshold in km/h below which the slow poll interval is used.
const double kLowSpeedThresholdKmh = 2.0;

/// Seconds without a GPS fix before emitting "gps_unavailable".
const int kGpsTimeoutSeconds = 30;

// ---------------------------------------------------------------------------
// Pure helper function
// ---------------------------------------------------------------------------

/// Builds a [VehicleState] payload from the given driver info and GPS [position].
///
/// Returns `null` if any input is invalid:
/// - [latitude] must be in [-90, 90]
/// - [longitude] must be in [-180, 180]
/// - [position.accuracy] must be > 0
/// - [routeId] must be non-empty
VehicleState? buildLocationPayload(
  String driverUID,
  String driverName,
  String routeId,
  Position position,
) {
  final lat = position.latitude;
  final lng = position.longitude;
  final acc = position.accuracy;

  if (lat < -90 || lat > 90) return null;
  if (lng < -180 || lng > 180) return null;
  if (acc <= 0) return null;
  if (routeId.trim().isEmpty) return null;

  return VehicleState(
    vehicleId: driverUID,
    driverName: driverName,
    routeId: routeId,
    latitude: lat,
    longitude: lng,
    accuracy: acc,
    heading: position.heading,
    speed: position.speed,
    timestamp: DateTime.now().millisecondsSinceEpoch,
    isActive: true,
  );
}

// ---------------------------------------------------------------------------
// LocationService
// ---------------------------------------------------------------------------

/// Manages GPS streaming for a driver and writes live [VehicleState] payloads
/// to Firebase Realtime Database.
class LocationService {
  // Status stream controller — broadcasts status strings to listeners.
  final StreamController<String> _statusController =
      StreamController<String>.broadcast();

  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription<DatabaseEvent>? _connectionSubscription;
  Timer? _gpsTimeoutTimer;

  DateTime? _lastWriteTime;

  // Tracks whether streaming is currently active (used by reconnect handler).
  bool _isStreaming = false;
  String? _activeDriverUID;
  String? _activeDriverName;
  String? _activeRouteId;

  /// Stream of status messages emitted by this service.
  ///
  /// Possible values: `"streaming"`, `"stopped"`, `"gps_unavailable"`,
  /// `"low_accuracy"`, `"permission_denied"`.
  Stream<String> get statusStream => _statusController.stream;

  // ---------------------------------------------------------------------------
  // startStreaming
  // ---------------------------------------------------------------------------

  /// Starts GPS streaming for the given driver.
  ///
  /// Steps:
  /// 1. Requests location permission; emits `"permission_denied"` and returns
  ///    if denied.
  /// 2. Registers an `onDisconnect` handler on RTDB so `isActive` is set to
  ///    `false` if the client disconnects unexpectedly.
  /// 3. Marks the vehicle as active on RTDB.
  /// 4. Subscribes to the high-accuracy position stream.
  /// 5. On each fix: validates accuracy, throttles writes, applies adaptive
  ///    poll interval, and writes the payload to RTDB.
  Future<void> startStreaming(
    String driverUID,
    String driverName,
    String routeId,
  ) async {
    // 1. Permission check.
    final status = await Permission.location.request();
    if (!status.isGranted) {
      _statusController.add('permission_denied');
      return;
    }

    final db = FirebaseDatabase.instance;
    final vehicleRef = db.ref('vehicles/$driverUID');

    // 2. Register onDisconnect so isActive is cleared on unexpected disconnect.
    await vehicleRef.child('isActive').onDisconnect().set(false);

    // 3. Mark vehicle as active on RTDB.
    await vehicleRef.update({
      'isActive': true,
      'routeId': routeId,
      'vehicleId': driverUID,
      'driverName': driverName,
    });

    // Track streaming state for reconnection handling.
    _isStreaming = true;
    _activeDriverUID = driverUID;
    _activeDriverName = driverName;
    _activeRouteId = routeId;

    // Listen to .info/connected — re-register onDisconnect after reconnection.
    _connectionSubscription?.cancel();
    _connectionSubscription = FirebaseDatabase.instance
        .ref('.info/connected')
        .onValue
        .listen((event) async {
      final connected = event.snapshot.value as bool? ?? false;
      if (connected && _isStreaming) {
        // Re-register the onDisconnect handler so it remains active after
        // each reconnection.
        await FirebaseDatabase.instance
            .ref('vehicles/$driverUID/isActive')
            .onDisconnect()
            .set(false);
      }
    });

    _statusController.add('streaming');

    // Reset timeout timer.
    _resetGpsTimeout(driverUID);

    // 4. Subscribe to position stream.
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
      ),
    ).listen(
      (position) => _onPosition(driverUID, driverName, routeId, position),
      onError: (_) => _statusController.add('gps_unavailable'),
    );
  }

  // ---------------------------------------------------------------------------
  // stopStreaming
  // ---------------------------------------------------------------------------

  /// Stops GPS streaming for the given driver and marks the vehicle inactive.
  Future<void> stopStreaming(String driverUID) async {
    _isStreaming = false;
    _activeDriverUID = null;
    _activeDriverName = null;
    _activeRouteId = null;

    _gpsTimeoutTimer?.cancel();
    _gpsTimeoutTimer = null;

    _connectionSubscription?.cancel();
    _connectionSubscription = null;

    await _positionSubscription?.cancel();
    _positionSubscription = null;

    _lastWriteTime = null;

    // Mark vehicle inactive on RTDB.
    await FirebaseDatabase.instance
        .ref('vehicles/$driverUID/isActive')
        .set(false);

    _statusController.add('stopped');
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Handles an incoming GPS [position] fix.
  Future<void> _onPosition(
    String driverUID,
    String driverName,
    String routeId,
    Position position,
  ) async {
    // Reset the GPS timeout on every received fix.
    _resetGpsTimeout(driverUID);

    // 5a. Accuracy gate.
    if (position.accuracy > kMaxAccuracyThreshold) {
      _statusController.add('low_accuracy');
      return;
    }

    // 7. Adaptive poll interval based on speed.
    final speedKmh = position.speed * 3.6; // m/s → km/h
    final intervalSeconds = speedKmh < kLowSpeedThresholdKmh
        ? kSlowPollIntervalSeconds
        : kPollIntervalSeconds;

    // 6. Throttle writes.
    final now = DateTime.now();
    if (_lastWriteTime != null) {
      final elapsed = now.difference(_lastWriteTime!).inSeconds;
      if (elapsed < intervalSeconds) return;
    }

    // 5b. Build payload.
    final payload =
        buildLocationPayload(driverUID, driverName, routeId, position);
    if (payload == null) return;

    // Write to RTDB.
    await FirebaseDatabase.instance
        .ref('vehicles/$driverUID')
        .set(payload.toJson());

    _lastWriteTime = now;
    _statusController.add('streaming');
  }

  /// Resets the GPS timeout timer. If no position is received within
  /// [kGpsTimeoutSeconds], emits `"gps_unavailable"`.
  void _resetGpsTimeout(String driverUID) {
    _gpsTimeoutTimer?.cancel();
    _gpsTimeoutTimer = Timer(
      Duration(seconds: kGpsTimeoutSeconds),
      () => _statusController.add('gps_unavailable'),
    );
  }

  /// Releases all resources held by this service.
  ///
  /// If streaming is still active when this is called (e.g. the widget was
  /// disposed without explicitly stopping), the RTDB `isActive` flag is set
  /// to `false` so the vehicle is removed from the student map.
  Future<void> dispose() async {
    if (_isStreaming && _activeDriverUID != null) {
      // Best-effort: mark inactive on RTDB before tearing down.
      try {
        await FirebaseDatabase.instance
            .ref('vehicles/$_activeDriverUID/isActive')
            .set(false);
      } catch (_) {
        // Ignore — the onDisconnect handler will clean up server-side.
      }
    }
    _isStreaming = false;
    _gpsTimeoutTimer?.cancel();
    _connectionSubscription?.cancel();
    await _positionSubscription?.cancel();
    _statusController.close();
  }
}
