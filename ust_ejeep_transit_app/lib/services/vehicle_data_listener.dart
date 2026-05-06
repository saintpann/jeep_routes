import 'dart:async';

import 'package:firebase_database/firebase_database.dart';

import '../models/models.dart';
import '../utils/staleness.dart';

/// Listens to the `/vehicles` node in Firebase Realtime Database and exposes
/// a filtered stream of active + recent [VehicleState] objects.
class VehicleDataListener {
  final StreamController<Map<String, VehicleState>> _controller =
      StreamController<Map<String, VehicleState>>.broadcast();

  StreamSubscription<DatabaseEvent>? _rtdbSubscription;
  Map<String, VehicleState> _latest = {};

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Filtered stream of active + recent vehicles.
  ///
  /// Emits a new snapshot whenever the underlying RTDB data changes.
  Stream<Map<String, VehicleState>> get vehicleStream => _controller.stream;

  /// Subscribes to `/vehicles` in Firebase RTDB.
  ///
  /// On each event the snapshot is parsed into a [Map<String, VehicleState>],
  /// filtered to only include vehicles where [VehicleState.isActive] is `true`
  /// AND [isRecent] returns `true` for the vehicle's timestamp, then pushed
  /// onto [vehicleStream].
  void subscribe() {
    _rtdbSubscription = FirebaseDatabase.instance
        .ref('vehicles')
        .onValue
        .listen(_onDatabaseEvent, onError: (_) {
      // Silently ignore RTDB errors; the stream will resume on reconnect.
    });
  }

  /// Cancels the RTDB subscription without closing the stream controller.
  void unsubscribe() {
    _rtdbSubscription?.cancel();
    _rtdbSubscription = null;
  }

  /// Returns the latest filtered snapshot synchronously.
  ///
  /// Returns an empty map if [subscribe] has not been called yet or no data
  /// has been received.
  Map<String, VehicleState> getActiveVehicles() => Map.unmodifiable(_latest);

  /// Cancels the RTDB subscription and closes the stream controller.
  void dispose() {
    unsubscribe();
    _controller.close();
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  void _onDatabaseEvent(DatabaseEvent event) {
    final snapshot = event.snapshot;
    final raw = snapshot.value;

    if (raw == null) {
      _latest = {};
      _controller.add({});
      return;
    }

    final Map<String, VehicleState> parsed = {};

    if (raw is Map) {
      for (final entry in raw.entries) {
        try {
          final vehicleMap = Map<String, dynamic>.from(entry.value as Map);
          final state = VehicleState.fromJson(vehicleMap);
          if (state.isActive && isRecent(state.timestamp)) {
            parsed[state.vehicleId] = state;
          }
        } catch (_) {
          // Skip malformed entries.
        }
      }
    }

    _latest = parsed;
    _controller.add(Map.unmodifiable(parsed));
  }
}
