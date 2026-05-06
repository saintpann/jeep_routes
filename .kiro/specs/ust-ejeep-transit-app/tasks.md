# Implementation Plan: UST E-Jeep Transit App with Real-time GPS Tracking

## Overview

This plan implements the UST E-Jeep Transit App as a Flutter (Dart) mobile application for Android and iOS, backed by Firebase Realtime Database, Firebase Authentication, Firestore, and Firebase Cloud Functions (TypeScript). Tasks are ordered to build incrementally — core data models and auth first, then GPS streaming, then the student map view, then ETA, and finally integration wiring and tests.

## Tasks

- [x] 1. Set up Flutter project structure and Firebase configuration
  - Create a new Flutter project (`flutter create ust_ejeep_transit_app`) with the standard `lib/` directory structure: `lib/models/`, `lib/services/`, `lib/screens/`, `lib/widgets/`, `lib/utils/`
  - Add Flutter dependencies to `pubspec.yaml`: `firebase_core`, `firebase_auth`, `firebase_database`, `cloud_firestore`, `cloud_functions`, `google_maps_flutter`, `geolocator`, `permission_handler`
  - Add dev dependencies: `flutter_test`, `mockito`, `build_runner`
  - Initialize Firebase in `lib/main.dart` using `Firebase.initializeApp()` with platform-specific `google-services.json` (Android) and `GoogleService-Info.plist` (iOS)
  - Create `firebase.json` and `.firebaserc` at the project root for Firebase CLI tooling; create `functions/` directory with `package.json` (TypeScript, Jest, fast-check), `tsconfig.json`, and `functions/src/index.ts` entry point
  - Configure `AndroidManifest.xml` with `ACCESS_FINE_LOCATION` and `ACCESS_COARSE_LOCATION` permissions; configure `Info.plist` with `NSLocationWhenInUseUsageDescription` and `NSLocationAlwaysUsageDescription`
  - _Requirements: 3.1, 10.5, 10.6_

- [x] 2. Define core data models
  - [x] 2.1 Implement `VehicleState` model in `lib/models/vehicle_state.dart`
    - Define all fields: `vehicleId`, `driverName`, `routeId`, `latitude`, `longitude`, `accuracy`, `heading`, `speed`, `timestamp`, `isActive`
    - Implement `toJson()` and `fromJson(Map<String, dynamic>)` factory constructor for RTDB serialization/deserialization
    - Implement `copyWith()` for immutable updates
    - _Requirements: 4.1, 10.3_

  - [x] 2.2 Implement `RouteGeoJSON` and `Stop` models in `lib/models/route_geojson.dart`
    - Define `RouteGeoJSON` with fields: `routeId`, `routeName`, `color`, `geometry` (GeoJSON LineString as `List<List<double>>`), `stops`
    - Define `Stop` with fields: `stopId`, `name`, `latitude`, `longitude`, `sequence`
    - Implement `toJson()` / `fromJson()` for both
    - _Requirements: 9.1, 9.2_

  - [x] 2.3 Implement `User`, `AuthResult`, and `ETAResult` models in `lib/models/`
    - Define `UserRole` enum: `DRIVER`, `STUDENT`, `ANONYMOUS`
    - Define `User` with fields: `uid`, `email`, `displayName`, `role`, `routeId`
    - Define `AuthResult` as a sealed class / discriminated union with `AuthSuccess` and `AuthFailure` variants
    - Define `ETAResult` as a sealed class with `ETAAvailable` and `ETAUnavailable` variants matching the design spec fields
    - _Requirements: 1.1, 1.2, 1.5, 2.1, 2.3_

  - [ ]* 2.4 Write property test for `VehicleState` serialization round-trip
    - **Property 6: Payload Completeness** — for any valid `VehicleState`, `fromJson(toJson(state))` returns an equal object with all fields non-null
    - **Validates: Requirements 4.1, 4.5**

  - [ ]* 2.5 Write property test for `VehicleState` payload size bound
    - **Property 10: Payload Size Bound** — for any valid `VehicleState`, `jsonEncode(state.toJson()).length` ≤ 500 bytes
    - **Validates: Requirements 10.3**

- [x] 3. Implement `AuthService`
  - [x] 3.1 Implement `AuthService` class in `lib/services/auth_service.dart`
    - Implement `signInDriver(email, password)` using `FirebaseAuth.signInWithEmailAndPassword`; return `AuthSuccess` with `role = DRIVER` on success, `AuthFailure` with descriptive `errorCode` on failure
    - Implement `signInStudentAnonymously()` using `FirebaseAuth.signInAnonymously()`; return `AuthSuccess` with `role = ANONYMOUS` on success
    - Implement null/empty credential guard: return `AuthFailure("MISSING_CREDENTIALS", ...)` before calling Firebase if email or password is null/empty for driver sign-in
    - Implement `signOut()`, `getCurrentUser()`, and `isDriver(user)` helpers
    - Implement silent token refresh by relying on the Firebase SDK's `authStateChanges()` stream; expose it for the app to react to session changes
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 2.1, 2.2, 2.3, 2.4, 11.1, 11.2, 12.1, 12.2, 12.3_

  - [ ]* 3.2 Write unit tests for `AuthService`
    - Mock `FirebaseAuth`; test driver sign-in success, driver sign-in failure (wrong password), missing credentials guard, anonymous sign-in success, anonymous sign-in failure, and sign-out
    - _Requirements: 1.1, 1.2, 1.3, 2.1, 2.2_

- [x] 4. Implement Driver and Student authentication screens
  - [x] 4.1 Create `DriverLoginScreen` in `lib/screens/driver_login_screen.dart`
    - Build a `StatefulWidget` with email and password `TextFormField` widgets and a "Sign In" button
    - Call `AuthService.signInDriver()` on submit; show a loading indicator while awaiting; navigate to `DriverScreen` on `AuthSuccess`; display `AuthFailure.message` in a `SnackBar` on failure
    - _Requirements: 1.1, 1.2, 1.3, 1.4_

  - [x] 4.2 Create `StudentEntryScreen` in `lib/screens/student_entry_screen.dart`
    - On screen load, call `AuthService.signInStudentAnonymously()` automatically; navigate to `StudentMapScreen` on `AuthSuccess`; show an error message with a retry button on `AuthFailure`
    - _Requirements: 2.1, 2.2, 2.4_

- [x] 5. Implement `LocationService` (Driver GPS streaming)
  - [x] 5.1 Implement `buildLocationPayload` in `lib/services/location_service.dart`
    - Implement the pure function `buildLocationPayload(driverUID, routeId, position)` that constructs a `VehicleState`
    - Validate: `latitude ∈ [-90, 90]`, `longitude ∈ [-180, 180]`, `accuracy > 0`, `routeId` is non-empty; throw `ArgumentError` (or return `null`) for invalid inputs
    - Set `timestamp` to `DateTime.now().millisecondsSinceEpoch`
    - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5, 4.6_

  - [ ]* 5.2 Write property test for `buildLocationPayload` coordinate validity
    - **Property 5: Coordinate Validity** — for any `latitude` outside [-90, 90] or `longitude` outside [-180, 180] or `accuracy ≤ 0`, `buildLocationPayload` rejects the payload; for valid inputs, the returned `VehicleState` preserves exact lat/lng values
    - **Validates: Requirements 4.2, 4.3, 4.4**

  - [ ]* 5.3 Write property test for `buildLocationPayload` completeness
    - **Property 6: Payload Completeness** — for any valid `(driverUID, routeId, position)`, all fields of the returned `VehicleState` are non-null
    - **Validates: Requirements 4.1, 4.5**

  - [x] 5.4 Implement `startStreaming` and `stopStreaming` in `LocationService`
    - Request location permissions using `permission_handler` before starting; abort with a user-facing error if denied
    - Register `onDisconnect("/vehicles/{driverUID}/isActive").set(false)` on the RTDB reference **before** writing any location data
    - Set `isActive = true` and `routeId` on the RTDB node at stream start
    - Use `geolocator.getPositionStream(locationSettings: LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 0))` to receive GPS updates
    - On each position event: skip if `accuracy > MAX_ACCURACY_THRESHOLD` (50 m); call `buildLocationPayload`; write to `/vehicles/{driverUID}` via `firebase_database`
    - Enforce `POLL_INTERVAL_SECONDS` (3 s) throttle between writes using a `Timer` or stream throttle
    - On `stopStreaming`: cancel the GPS stream subscription; set `isActive = false` at `/vehicles/{driverUID}/isActive`
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 10.1, 10.5_

  - [x] 5.5 Implement adaptive poll interval (stationary detection) in `LocationService`
    - When `vehicle.speed < LOW_SPEED_THRESHOLD_KMH` (e.g., 2 km/h), increase poll interval to 5 seconds; revert to 3 seconds when speed rises above threshold
    - _Requirements: 10.2_

  - [ ]* 5.6 Write property test for timestamp monotonicity
    - **Property 7: Timestamp Monotonicity** — for any sequence of consecutive payloads produced by `buildLocationPayload` with increasing wall-clock time, each payload's `timestamp` is strictly greater than the previous
    - **Validates: Requirements 3.5**

- [x] 6. Implement `isRecent` staleness utility
  - [x] 6.1 Implement `isRecent(timestamp)` in `lib/utils/staleness.dart`
    - Return `true` if `DateTime.now().millisecondsSinceEpoch - timestamp <= STALE_THRESHOLD_MS` (30,000 ms)
    - Export `STALE_THRESHOLD_MS` as a top-level constant
    - _Requirements: 6.1, 6.2_

  - [ ]* 6.2 Write property test for staleness monotonicity
    - **Property 2: Staleness Monotonicity** — for any two timestamps `t1 < t2`, if `isRecent(t1) = true` then `isRecent(t2) = true`
    - **Validates: Requirements 6.3**

- [x] 7. Implement `RouteDataService`
  - [x] 7.1 Implement `RouteDataService` in `lib/services/route_data_service.dart`
    - Bundle a `assets/routes.geojson` file in the Flutter project with at least two sample UST-area E-Jeep routes (GeoJSON FeatureCollection)
    - Implement `loadRoutes()`: load from `rootBundle.loadString('assets/routes.geojson')`, parse into `List<RouteGeoJSON>`, and cache in memory
    - Implement `getRouteById(routeId)` and `getStopsForRoute(routeId)` using the in-memory cache
    - Implement local disk caching using `shared_preferences` or `path_provider` + file I/O so routes are available offline after first load
    - _Requirements: 9.1, 9.5, 9.6_

  - [ ]* 7.2 Write unit tests for `RouteDataService`
    - Test that `loadRoutes()` returns the same set of routes from cache and from the bundled asset
    - Test `getRouteById` returns `null` for unknown IDs
    - _Requirements: 9.5, 9.6_

- [x] 8. Implement Firebase RTDB Security Rules
  - [x] 8.1 Write RTDB security rules in `database.rules.json`
    - Allow authenticated drivers to read and write only to `/vehicles/{uid}` where `uid == auth.uid`
    - Allow any authenticated user (including anonymous) to read `/vehicles`
    - Deny all writes to `/vehicles` for unauthenticated clients
    - Deny drivers from writing to another driver's UID path
    - _Requirements: 8.1, 8.2, 8.3, 8.4, 8.5_

  - [ ]* 8.2 Write integration tests for security rules using Firebase Emulator Suite
    - **Property 8: Driver Isolation** — test that a driver with UID `d1` cannot write to `/vehicles/d2`
    - **Property 9: Student Read-Only Access** — test that an anonymous session can read `/vehicles` but cannot write to any path under `/vehicles`
    - Use the Firebase Emulator REST API or `@firebase/rules-unit-testing` in the `functions/` test suite
    - **Validates: Requirements 8.1, 8.2, 8.3, 8.4, 8.5**

- [ ] 9. Checkpoint — Core services complete
  - Ensure all tests pass, ask the user if questions arise.

- [x] 10. Implement `VehicleDataListener`
  - [x] 10.1 Implement `VehicleDataListener` in `lib/services/vehicle_data_listener.dart`
    - Subscribe to `/vehicles` using `FirebaseDatabase.instance.ref('vehicles').onValue`
    - On each `DatabaseEvent`, parse the snapshot into `Map<String, VehicleState>` using `VehicleState.fromJson`
    - Filter out vehicles where `isActive == false` OR `isRecent(timestamp) == false` before dispatching
    - Expose a `Stream<Map<String, VehicleState>>` of active vehicles for the UI to consume
    - Implement `unsubscribe()` to cancel the stream subscription
    - Implement `getActiveVehicles()` returning the latest filtered snapshot synchronously
    - _Requirements: 5.1, 5.2, 5.3, 5.4, 6.4, 7.1, 7.2, 7.3, 7.4_

  - [ ]* 10.2 Write unit tests for `VehicleDataListener`
    - Mock RTDB stream; test that inactive vehicles are filtered out, stale vehicles are filtered out, and active+recent vehicles are passed through
    - _Requirements: 5.3, 5.4, 6.4_

- [x] 11. Implement `MapRenderer` widget and student map view
  - [x] 11.1 Create `StudentMapScreen` in `lib/screens/student_map_screen.dart`
    - Build a `StatefulWidget` wrapping a `GoogleMap` widget from `google_maps_flutter`
    - Initialize the map centered on UST coordinates (14.6097° N, 120.9897° E) with a zoom level of 15
    - Subscribe to `VehicleDataListener`'s stream in `initState`; call `onVehicleDataUpdate` on each emission
    - Dispose the listener subscription in `dispose()`
    - _Requirements: 5.1, 5.2_

  - [x] 11.2 Implement `onVehicleDataUpdate` marker management in `StudentMapScreen`
    - Maintain a `Map<String, Marker>` of current markers keyed by `vehicleId`
    - On each snapshot: add `BitmapDescriptor`-colored markers for new active+recent vehicles; call `marker.copyWith(positionParam: ...)` to update existing markers in place (no flicker); remove markers for vehicles no longer in the active set
    - Color each marker using the `color` field from `RouteDataService.getRouteById(vehicle.routeId)`; use a default grey marker if `routeId` is unknown
    - Call `setState(() { _markers = updatedMarkers; })` once per update cycle
    - _Requirements: 5.2, 5.3, 5.4, 5.5, 5.6, 9.2, 9.3, 10.4_

  - [ ]* 11.3 Write property test for marker consistency
    - **Property 3: Marker Consistency** — for any snapshot, after `onVehicleDataUpdate` the set of marker IDs equals exactly the set of `vehicleId`s where `isActive = true` AND `isRecent(timestamp) = true`
    - **Validates: Requirements 5.3, 5.4, 5.5**

  - [ ]* 11.4 Write property test for marker idempotency
    - **Property 4: Marker Idempotency** — calling `onVehicleDataUpdate(snapshot)` twice with the same snapshot produces the same marker state as calling it once
    - **Validates: Requirements 5.6**

  - [ ]* 11.5 Write property test for location freshness
    - **Property 1: Location Freshness** — for any marker present on the map after `onVehicleDataUpdate`, the corresponding vehicle's `timestamp` satisfies `isRecent(timestamp) = true`
    - **Validates: Requirements 5.3, 6.1, 6.2**

- [x] 12. Implement GeoJSON route overlay rendering
  - [x] 12.1 Render route polylines on the `GoogleMap` in `StudentMapScreen`
    - In `initState`, call `RouteDataService.loadRoutes()` and convert each `RouteGeoJSON.geometry` into a `Polyline` object using the route's `color` field
    - Add stop markers as small `Marker` objects with a distinct icon; include `stopId` and `name` in the marker's `infoWindow`
    - Add all `Polyline` and stop `Marker` objects to the `GoogleMap` widget's `polylines` and `markers` sets
    - _Requirements: 9.1, 9.2, 9.4_

  - [x] 12.2 Implement vehicle marker info window (tap popup)
    - Set each vehicle `Marker`'s `infoWindow` to display `driverName`, `routeId`, and a human-readable `timestamp` (e.g., "Updated 5s ago") using `DateTime.fromMillisecondsSinceEpoch`
    - _Requirements: 9.4_

  - [ ]* 12.3 Write unit tests for route color consistency
    - **Property 11: Route Color Consistency** — for any vehicle marker with a known `routeId`, the marker color matches `RouteDataService.getRouteById(routeId).color`
    - **Validates: Requirements 9.2**

- [x] 13. Implement `DriverScreen` with streaming controls
  - [x] 13.1 Create `DriverScreen` in `lib/screens/driver_screen.dart`
    - Build a `StatefulWidget` with a "Start Streaming" / "Stop Streaming" toggle button and a status indicator (streaming / stopped / GPS unavailable)
    - On "Start Streaming": call `LocationService.startStreaming(driverUID, routeId)`; update UI state to show streaming status
    - On "Stop Streaming": call `LocationService.stopStreaming(driverUID)`; update UI state
    - Display a warning banner when GPS accuracy exceeds `MAX_ACCURACY_THRESHOLD` or GPS is unavailable (Requirement 3.6)
    - Display current speed and accuracy readings while streaming
    - On sign-out button tap: call `AuthService.signOut()` and navigate back to `DriverLoginScreen`; `LocationService.stopStreaming()` is called first
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.6, 12.3_

  - [ ]* 13.2 Write unit tests for `LocationService` low-accuracy rejection
    - **Property 12: Low-Accuracy Rejection** — mock GPS stream; verify that when `accuracy > MAX_ACCURACY_THRESHOLD`, no write is made to RTDB
    - **Validates: Requirements 3.3**

- [x] 14. Implement offline and reconnection handling
  - [x] 14.1 Implement student offline banner in `StudentMapScreen`
    - Listen to `FirebaseDatabase.instance.ref('.info/connected')` for connection state changes
    - When `connected == false`, show a persistent `MaterialBanner` with "Reconnecting…" text
    - When `connected == true`, dismiss the banner; the RTDB listener automatically delivers a fresh snapshot
    - _Requirements: 7.3, 7.4_

  - [x] 14.2 Implement driver reconnection resume in `LocationService`
    - Listen to `FirebaseDatabase.instance.ref('.info/connected')`; when connection is restored after a drop, set `isActive = true` on the next successful RTDB write (the streaming loop handles this naturally since it writes on each poll)
    - Re-register the `onDisconnect` handler after each reconnection to ensure it remains active
    - _Requirements: 7.5_

- [ ] 15. Checkpoint — Flutter app feature-complete
  - Ensure all tests pass, ask the user if questions arise.

- [x] 16. Implement ETA Cloud Function (TypeScript)
  - [x] 16.1 Implement `projectOntoRoute` in `functions/src/geo_utils.ts`
    - Implement `haversineDistance(lat1, lng1, lat2, lng2): number` returning distance in metres
    - Implement `closestPointOnSegment(px, py, ax, ay, bx, by): {lat: number, lng: number}` using vector projection
    - Implement `projectOntoRoute(latitude, longitude, coordinates: number[][]): RouteProgress` following the design pseudocode
    - Ensure `progressFraction` is clamped to [0, 1] and `distanceTravelledM ≤ totalRouteLengthM`
    - _Requirements: (ETA calculation correctness)_

  - [ ]* 16.2 Write property test for `projectOntoRoute` bounds (fast-check)
    - **Property 16: Route Progress Fraction Bounds** — use `fc.float` generators for coordinates within a bounding box around UST; assert `progressFraction ∈ [0, 1]` and `distanceTravelledM ≤ totalRouteLengthM` for all generated inputs
    - **Validates: Route projection correctness**

  - [x] 16.3 Implement `calculateETA` Cloud Function in `functions/src/index.ts`
    - Export an HTTPS Callable function `calculateETA` using `functions.https.onCall`
    - Implement the full algorithm from the design: fetch vehicle from RTDB, check `isActive` and `isRecent`, load route, find stop, call `projectOntoRoute`, compute `remainingDistanceM`, compute `estimatedArrivalSec` using `vehicle.speed` (fallback to `DEFAULT_SPEED_MPS = 5.56`), determine confidence level, return `ETAResult`
    - Return `ETAResult.Unavailable` with appropriate reason strings for all error cases (`VEHICLE_INACTIVE`, `STALE_POSITION`, `UNKNOWN_ROUTE`, `UNKNOWN_STOP`, `STOP_PASSED`)
    - Ensure `estimatedArrivalSec` is always `Math.max(0, Math.round(...))` — never negative
    - _Requirements: (ETA calculation, confidence levels)_

  - [ ]* 16.4 Write property test for ETA non-negativity (fast-check)
    - **Property 13: ETA Non-Negativity** — for any active, recent vehicle and any reachable stop, `calculateETA` never returns a negative `estimatedArrivalSec`
    - Use `fc.record` generators to produce valid `VehicleState` and `Stop` combinations
    - **Validates: ETA calculation correctness**

  - [ ]* 16.5 Write property test for ETA unavailability for inactive vehicles (fast-check)
    - **Property 14: ETA Unavailability for Inactive Vehicles** — for any vehicle where `isActive = false` OR `isRecent(timestamp) = false`, `calculateETA` returns `ETAResult.Unavailable`
    - **Validates: ETA data freshness**

  - [ ]* 16.6 Write property test for ETA unavailability for passed stops (fast-check)
    - **Property 15: ETA Unavailability for Passed Stops** — for any vehicle whose projected `distanceTravelledM ≥` stop's `distanceTravelledM`, `calculateETA` returns `ETAResult.Unavailable("STOP_PASSED")`
    - **Validates: ETA directional correctness**

  - [ ]* 16.7 Write property test for ETA confidence monotonicity (fast-check)
    - **Property 17: ETA Confidence Monotonicity** — for two ETA computations for the same vehicle/stop where position age at `t2 > t1`, confidence at `t2 ≤` confidence at `t1`
    - **Validates: ETA confidence accuracy**

- [x] 17. Implement ETA display in Flutter UI
  - [x] 17.1 Implement `ETAService` client in `lib/services/eta_service.dart`
    - Implement `calculateETA(vehicleId, stopId, routeId)` using `FirebaseFunctions.instance.httpsCallable('calculateETA').call({...})`
    - Parse the response map into `ETAResult` (either `ETAAvailable` or `ETAUnavailable`)
    - Cache the last `ETAResult` per `stopId` for up to 10 seconds to avoid redundant calls
    - Handle `FirebaseFunctionsException` and network errors; return `ETAUnavailable("SERVICE_ERROR")` on failure
    - _Requirements: (ETA display, performance)_

  - [x] 17.2 Implement ETA display on stop marker tap in `StudentMapScreen`
    - When a student taps a stop marker, call `ETAService.calculateETA(nearestVehicleId, stopId, routeId)`
    - Show a `BottomSheet` or `AlertDialog` with the ETA in minutes (e.g., "E-Jeep arriving in ~3 min") for `ETAAvailable`, or "ETA unavailable: [reason]" for `ETAUnavailable`
    - Call `MapRenderer.displayETABadge` by overlaying a `Text` widget on the stop marker position using a `Stack` + `Positioned` approach
    - _Requirements: 9.4_

- [x] 18. Implement Firestore driver profile storage
  - [x] 18.1 Create Firestore security rules in `firestore.rules`
    - Allow authenticated drivers to read their own profile document at `/drivers/{uid}`
    - Allow admin-only writes (use a custom claim `admin: true` or a separate admin SDK path)
    - Deny anonymous students from reading `/drivers` collection
    - _Requirements: 11.3, 11.4_

  - [x] 18.2 Implement driver profile read in `AuthService`
    - After successful driver sign-in, fetch the driver's Firestore document at `/drivers/{uid}` to populate `User.displayName` and `User.routeId`
    - If the Firestore document does not exist, return `AuthFailure("ACCOUNT_NOT_PROVISIONED", ...)`
    - _Requirements: 11.1, 11.2_

- [ ] 19. Integration tests with Firebase Emulator Suite
  - [ ]* 19.1 Write integration test: Driver → RTDB → Student pipeline
    - Start Firebase Emulator Suite (`firebase emulators:start`) in the test setup
    - Simulate a driver writing a `VehicleState` to `/vehicles/{driverUID}` via the Emulator REST API
    - Assert that a `VehicleDataListener` subscriber receives the update within 1 second
    - Assert that the resulting marker set contains exactly the written vehicle
    - _Requirements: 5.1, 5.2, 7.1_

  - [ ]* 19.2 Write integration test: `onDisconnect` behavior
    - Using the Firebase Emulator, simulate a driver connection drop by calling the Emulator's `DELETE /emulator/v1/projects/{project}/databases/.../connections/{connectionId}` endpoint
    - Assert that `/vehicles/{driverUID}/isActive` is set to `false` after the disconnect
    - Assert that a subscribed `VehicleDataListener` removes the vehicle marker
    - _Requirements: 7.1, 7.2_

  - [ ]* 19.3 Write integration test: ETA Cloud Function end-to-end
    - Deploy `calculateETA` to the Functions Emulator
    - Seed RTDB Emulator with a mock `VehicleState` at a known position on a test route
    - Invoke `calculateETA` callable with a known `stopId` ahead of the vehicle
    - Assert the returned `ETAResult` is `Available` with `estimatedArrivalSec ≥ 0`
    - Assert that calling with a stop behind the vehicle returns `Unavailable("STOP_PASSED")`
    - _Requirements: (ETA end-to-end correctness)_

- [ ] 20. Final checkpoint — Ensure all tests pass
  - Run `flutter test` for all Dart unit and property tests
  - Run `npm test` (Jest + fast-check) in `functions/` for all Cloud Function tests
  - Run Firebase Emulator integration tests
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP delivery
- Each task references specific requirements for traceability
- Checkpoints at tasks 9, 15, and 20 ensure incremental validation
- Property tests (Properties 1–17) validate universal correctness guarantees; unit tests validate specific examples and edge cases
- The Firebase Emulator Suite must be running locally for integration tests (tasks 19.1–19.3)
- `google_maps_flutter` requires a valid Google Maps API key in `AndroidManifest.xml` and `AppDelegate.swift`/`AppDelegate.m`
- Driver accounts must be provisioned in Firebase Auth + Firestore before the driver login flow can be tested end-to-end
