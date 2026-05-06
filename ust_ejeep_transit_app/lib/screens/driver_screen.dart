import 'dart:async';

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/services.dart';

/// Driver screen with GPS streaming controls and status indicator.
///
/// Receives the authenticated [User] from [DriverLoginScreen] after sign-in.
class DriverScreen extends StatefulWidget {
  final User user;

  const DriverScreen({super.key, required this.user});

  @override
  State<DriverScreen> createState() => _DriverScreenState();
}

class _DriverScreenState extends State<DriverScreen> {
  bool _isStreaming = false;
  String _status = 'stopped';

  final LocationService _locationService = LocationService();
  StreamSubscription<String>? _statusSubscription;

  @override
  void initState() {
    super.initState();
    _statusSubscription = _locationService.statusStream.listen((status) {
      if (mounted) {
        setState(() {
          _status = status;
          // If permission was denied or streaming stopped externally,
          // reset the button state so the driver can try again.
          if (status == 'permission_denied' || status == 'stopped') {
            _isStreaming = false;
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _statusSubscription?.cancel();
    // LocationService.dispose() is async (sets isActive=false on RTDB).
    // We fire-and-forget here since dispose() must be synchronous in Flutter,
    // but the onDisconnect handler provides the server-side safety net.
    _locationService.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Streaming controls
  // ---------------------------------------------------------------------------

  Future<void> _startStreaming() async {
    // Set _isStreaming optimistically so the button flips immediately.
    // It will be corrected by the statusStream listener if permission is denied.
    setState(() => _isStreaming = true);
    await _locationService.startStreaming(
      widget.user.uid,
      widget.user.displayName ?? 'Driver',
      widget.user.routeId ?? 'unknown',
    );
  }

  Future<void> _stopStreaming() async {
    await _locationService.stopStreaming(widget.user.uid);
    if (mounted) {
      setState(() => _isStreaming = false);
    }
  }

  Future<void> _signOut() async {
    if (_isStreaming) {
      await _locationService.stopStreaming(widget.user.uid);
    }
    await AuthService().signOut();
    if (mounted) {
      // Clear the entire navigation stack and go back to role selection.
      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
    }
  }

  // ---------------------------------------------------------------------------
  // Status helpers
  // ---------------------------------------------------------------------------

  Color _statusColor(String status) {
    return switch (status) {
      'streaming' => Colors.green,
      'stopped' => Colors.grey,
      'gps_unavailable' => Colors.red,
      'low_accuracy' => Colors.orange,
      'permission_denied' => Colors.red,
      _ => Colors.grey,
    };
  }

  String _statusLabel(String status) {
    return switch (status) {
      'streaming' => 'Streaming',
      'stopped' => 'Stopped',
      'gps_unavailable' => 'GPS Unavailable',
      'low_accuracy' => 'Low Accuracy',
      'permission_denied' => 'Permission Denied',
      _ => status,
    };
  }

  bool get _showWarningBanner =>
      _status == 'gps_unavailable' || _status == 'low_accuracy';

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Driver Dashboard'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: _signOut,
          ),
        ],
      ),
      body: Column(
        children: [
          // Warning banner for GPS issues.
          if (_showWarningBanner)
            MaterialBanner(
              backgroundColor: Colors.orange.shade100,
              leading: const Icon(Icons.warning_amber_rounded,
                  color: Colors.orange),
              content: Text(
                _status == 'gps_unavailable'
                    ? 'GPS signal unavailable. Please move to an open area.'
                    : 'GPS accuracy is low. Location updates may be imprecise.',
                style: const TextStyle(color: Colors.black87),
              ),
              actions: [
                TextButton(
                  onPressed: () => setState(() {}),
                  child: const Text('Dismiss'),
                ),
              ],
            ),

          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Driver info card.
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.user.displayName ?? 'Driver',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Route: ${widget.user.routeId ?? 'Not assigned'}',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: Colors.black54),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Status indicator.
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: _statusColor(_status),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _statusLabel(_status),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: _statusColor(_status),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 40),

                  // Start / Stop streaming button.
                  SizedBox(
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: _isStreaming
                          ? _stopStreaming
                          : _startStreaming,
                      icon: Icon(
                        _isStreaming
                            ? Icons.stop_circle_outlined
                            : Icons.play_circle_outline,
                      ),
                      label: Text(
                        _isStreaming
                            ? 'Stop Streaming'
                            : 'Start Streaming',
                        style: const TextStyle(fontSize: 16),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            _isStreaming ? Colors.red : Colors.green,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
