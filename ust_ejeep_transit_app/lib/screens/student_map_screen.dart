import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/models.dart';
import '../services/services.dart';

/// Student-facing live map screen showing E-Jeep positions, route overlays,
/// and stop markers with ETA on tap.
class StudentMapScreen extends StatefulWidget {
  const StudentMapScreen({super.key});

  @override
  State<StudentMapScreen> createState() => _StudentMapScreenState();
}

class _StudentMapScreenState extends State<StudentMapScreen> {
  // Map controller
  GoogleMapController? _mapController;

  // Marker sets
  Map<MarkerId, Marker> _vehicleMarkers = {};
  Map<MarkerId, Marker> _stopMarkers = {};

  // Route overlays
  Set<Polyline> _routePolylines = {};

  // Services
  final VehicleDataListener _vehicleListener = VehicleDataListener();
  final RouteDataService _routeService = RouteDataService();

  // Subscriptions
  StreamSubscription<Map<String, VehicleState>>? _vehicleSubscription;
  StreamSubscription<DatabaseEvent>? _connectionSubscription;

  // State
  bool _isConnected = true;
  List<RouteGeoJSON> _routes = [];

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _loadRoutes();

    // Subscribe to vehicle updates.
    _vehicleListener.subscribe();
    _vehicleSubscription = _vehicleListener.vehicleStream.listen(
      _onVehicleDataUpdate,
    );

    // Listen to Firebase connection state.
    _connectionSubscription = FirebaseDatabase.instance
        .ref('.info/connected')
        .onValue
        .listen((event) {
      final connected = event.snapshot.value as bool? ?? false;
      if (mounted) {
        setState(() => _isConnected = connected);
      }
    });
  }

  @override
  void dispose() {
    _vehicleSubscription?.cancel();
    _connectionSubscription?.cancel();
    _vehicleListener.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Route loading (Tasks 12.1)
  // ---------------------------------------------------------------------------

  Future<void> _loadRoutes() async {
    final routes = await _routeService.loadRoutes();

    final Set<Polyline> polylines = {};
    final Map<MarkerId, Marker> stopMarkers = {};

    for (final route in routes) {
      // Build polyline — GeoJSON is [lng, lat], flip to LatLng(lat, lng).
      final points = route.geometry
          .map((coord) => LatLng(coord[1], coord[0]))
          .toList();

      polylines.add(Polyline(
        polylineId: PolylineId(route.routeId),
        color: _parseColor(route.color),
        width: 4,
        points: points,
      ));

      // Build stop markers.
      for (final stop in route.stops) {
        final markerId = MarkerId(stop.stopId);
        stopMarkers[markerId] = Marker(
          markerId: markerId,
          position: LatLng(stop.latitude, stop.longitude),
          icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueOrange),
          infoWindow: InfoWindow(title: stop.name),
          onTap: () => _onStopTapped(stop, route.routeId),
        );
      }
    }

    if (mounted) {
      setState(() {
        _routes = routes;
        _routePolylines = polylines;
        _stopMarkers = stopMarkers;
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Vehicle marker management (Tasks 11.2, 12.2)
  // ---------------------------------------------------------------------------

  void _onVehicleDataUpdate(Map<String, VehicleState> snapshot) {
    final Map<MarkerId, Marker> newMarkers = {};

    for (final vehicle in snapshot.values) {
      final markerId = MarkerId(vehicle.vehicleId);

      // Determine marker hue from route color.
      final double hue = _hueForRouteId(vehicle.routeId);

      newMarkers[markerId] = Marker(
        markerId: markerId,
        position: LatLng(vehicle.latitude, vehicle.longitude),
        icon: BitmapDescriptor.defaultMarkerWithHue(hue),
        infoWindow: InfoWindow(
          title: vehicle.driverName,
          snippet:
              'Route: ${vehicle.routeId} • Updated ${_timeAgo(vehicle.timestamp)}',
        ),
      );
    }

    if (mounted) {
      setState(() => _vehicleMarkers = newMarkers);
    }
  }

  /// Returns a Google Maps marker hue based on the route's color string.
  double _hueForRouteId(String routeId) {
    try {
      final route = _routes.firstWhere((r) => r.routeId == routeId);
      final color = _parseColor(route.color);
      // Extract RGB components (0–255 range).
      final r = (color.value >> 16) & 0xFF;
      final g = (color.value >> 8) & 0xFF;
      final b = color.value & 0xFF;

      // Blue-ish routes → hue 210
      if (b > r && b > g) return BitmapDescriptor.hueBlue;
      // Green-ish routes → hue 120
      if (g > r && g > b) return BitmapDescriptor.hueGreen;
      // Red-ish routes → hue 0
      if (r > g && r > b) return BitmapDescriptor.hueRed;
      // Yellow-ish
      if (r > b && g > b) return BitmapDescriptor.hueYellow;
    } catch (_) {
      // Route not found — fall through to default.
    }
    return BitmapDescriptor.hueRed; // default
  }

  // ---------------------------------------------------------------------------
  // Stop tap → ETA bottom sheet (Task 17.2 / 11.1)
  // ---------------------------------------------------------------------------

  void _onStopTapped(Stop stop, String routeId) {
    // Find the nearest active vehicle on the same route.
    final activeVehicles = _vehicleListener.getActiveVehicles();
    final routeVehicles = activeVehicles.values
        .where((v) => v.routeId == routeId)
        .toList();

    VehicleState? nearest;
    if (routeVehicles.isNotEmpty) {
      // Pick the first one (nearest logic can be improved later).
      nearest = routeVehicles.first;
    }

    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => _ETABottomSheet(
        stop: stop,
        vehicle: nearest,
        routeId: routeId,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Returns a human-readable "X ago" string for a millisecond [timestamp].
  String _timeAgo(int timestamp) {
    final ageMs =
        DateTime.now().millisecondsSinceEpoch - timestamp;
    final ageSec = (ageMs / 1000).round();
    if (ageSec < 60) return '${ageSec}s ago';
    return '${(ageSec / 60).round()}m ago';
  }

  /// Parses a "#RRGGBB" hex color string to a Flutter [Color].
  Color _parseColor(String hex) {
    final cleaned = hex.replaceFirst('#', '');
    if (cleaned.length == 6) {
      return Color(int.parse('FF$cleaned', radix: 16));
    }
    return Colors.blue; // fallback
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final allMarkers = {
      ..._stopMarkers,
      ..._vehicleMarkers,
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('UST E-Jeep Live Map'),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: const CameraPosition(
              target: LatLng(14.6097, 120.9897),
              zoom: 15,
            ),
            markers: Set<Marker>.of(allMarkers.values),
            polylines: _routePolylines,
            onMapCreated: (controller) {
              _mapController = controller;
            },
            myLocationButtonEnabled: false,
          ),
          if (!_isConnected)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Material(
                color: Colors.amber.shade700,
                child: const Padding(
                  padding:
                      EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                  child: Row(
                    children: [
                      Icon(Icons.wifi_off, color: Colors.white, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'Reconnecting…',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// ETA Bottom Sheet widget
// ---------------------------------------------------------------------------

class _ETABottomSheet extends StatefulWidget {
  final Stop stop;
  final VehicleState? vehicle;
  final String routeId;

  const _ETABottomSheet({
    required this.stop,
    required this.vehicle,
    required this.routeId,
  });

  @override
  State<_ETABottomSheet> createState() => _ETABottomSheetState();
}

class _ETABottomSheetState extends State<_ETABottomSheet> {
  ETAResult? _etaResult;
  // Start as true when a vehicle is present so the loading spinner shows
  // immediately — avoids a flash of "ETA unavailable." before the fetch.
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    if (widget.vehicle != null) {
      _loading = true;
      _fetchETA();
    }
  }

  Future<void> _fetchETA() async {
    final result = await ETAService().calculateETA(
      widget.vehicle!.vehicleId,
      widget.stop.stopId,
      widget.routeId,
    );
    if (mounted) {
      setState(() {
        _etaResult = result;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.stop.name,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          if (widget.vehicle == null)
            const Text('No active E-Jeep on this route.')
          else if (_loading)
            const Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 12),
                Text('Calculating ETA…'),
              ],
            )
          else if (_etaResult == null)
            const Text('ETA unavailable.')
          else
            _buildETAContent(_etaResult!),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildETAContent(ETAResult result) {
    return switch (result) {
      ETAAvailable(:final estimatedArrivalSec) => Text(
          'E-Jeep arriving in ~${(estimatedArrivalSec / 60).ceil()} min',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.green,
          ),
        ),
      ETAUnavailable(:final reason) => Text(
          'ETA unavailable: $reason',
          style: const TextStyle(color: Colors.red),
        ),
    };
  }
}
