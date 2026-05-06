# Requirements Document

## Introduction

The UST E-Jeep Transit App enables private electric jeepney (E-Jeep) drivers operating near the University of Santo Tomas (UST) in Manila, Philippines to stream their live GPS location to a Firebase Realtime Database. Students and commuters can view all active E-Jeeps on a custom-drawn route map in real time, helping them plan their commute and reduce waiting time at stops.

The system supports two user roles — **Driver** and **Student/Passenger** — backed by Firebase Realtime Database for live location data and Firebase Authentication for identity management. The map is rendered using a custom GeoJSON route overlay on top of a base map provider (Google Maps or OpenStreetMap/Leaflet).

---

## Glossary

- **Driver**: An authenticated E-Jeep operator who streams their GPS location to the system.
- **Student**: A passenger or commuter who views live vehicle positions on the map. May authenticate anonymously.
- **LocationService**: The component responsible for collecting GPS coordinates and writing them to Firebase RTDB.
- **MapRenderer**: The component responsible for rendering the route overlay and vehicle markers on the base map.
- **VehicleDataListener**: The component that subscribes to the `/vehicles` node in Firebase RTDB and dispatches updates to the MapRenderer.
- **AuthService**: The component that manages sign-in flows for both Drivers and Students.
- **RouteDataService**: The component that loads and caches static GeoJSON route definitions.
- **RTDB**: Firebase Realtime Database — the backend store for live vehicle location data.
- **VehicleState**: The data structure representing a single vehicle's current position and status.
- **RouteGeoJSON**: The data structure representing a single E-Jeep route's geometry and stops.
- **isActive**: A boolean field on VehicleState indicating whether the Driver is currently streaming.
- **isRecent**: A function that returns `true` if a vehicle's `timestamp` is within `STALE_THRESHOLD_MS` of the current time.
- **STALE_THRESHOLD_MS**: The maximum age (in milliseconds) of a vehicle update before it is considered stale. Default: 30,000 ms (30 seconds).
- **MAX_ACCURACY_THRESHOLD**: The maximum acceptable GPS accuracy radius in meters. Readings with accuracy above this value are discarded. Default: 50 m.
- **POLL_INTERVAL_SECONDS**: The interval in seconds between consecutive GPS writes. Default: 3 seconds.
- **onDisconnect**: A Firebase RTDB mechanism that executes a write operation server-side when a client's connection is lost.
- **Anonymous Auth**: Firebase Authentication sign-in that creates a temporary, credential-free session for Students.
- **driverUID**: The Firebase Authentication UID assigned to a Driver upon successful sign-in.

---

## Requirements

### Requirement 1: Driver Authentication

**User Story:** As an E-Jeep driver, I want to sign in with my email and password, so that I can be identified and authorized to stream my GPS location.

#### Acceptance Criteria

1. WHEN a Driver provides a valid email and password, THE AuthService SHALL authenticate the Driver and return an `AuthResult.Success` containing a non-null `user` object and a non-null `token`.
2. WHEN a Driver provides an invalid email or incorrect password, THE AuthService SHALL return an `AuthResult.Failure` containing a non-empty `errorCode` and a non-empty human-readable `message`.
3. IF a Driver submits a sign-in request with a null or empty email or a null or empty password, THEN THE AuthService SHALL return an `AuthResult.Failure` with `errorCode` "MISSING_CREDENTIALS" without contacting Firebase Auth.
4. WHEN a Driver authentication attempt fails due to a network error, THE AuthService SHALL return an `AuthResult.Failure` with a descriptive `errorCode` and allow the Driver to retry.
5. THE AuthService SHALL assign the `DRIVER` role to the `User` object returned in every successful Driver sign-in response.

---

### Requirement 2: Student Authentication

**User Story:** As a student or commuter, I want to access the live map without creating an account, so that I can view E-Jeep locations immediately without friction.

#### Acceptance Criteria

1. WHEN a Student initiates anonymous sign-in, THE AuthService SHALL call Firebase Anonymous Authentication and return an `AuthResult.Success` containing a non-null `token`.
2. WHEN anonymous sign-in fails, THE AuthService SHALL return an `AuthResult.Failure` with a descriptive `errorCode` and `message`.
3. THE AuthService SHALL assign the `ANONYMOUS` role to the `User` object returned in every successful anonymous sign-in response.
4. THE AuthService SHALL NOT require a Student to provide an email address or password to access the map.

---

### Requirement 3: Driver GPS Location Streaming

**User Story:** As an E-Jeep driver, I want my GPS location to be continuously sent to the server while I am on duty, so that students can see where my vehicle is in real time.

#### Acceptance Criteria

1. WHEN a Driver starts a streaming session, THE LocationService SHALL register an `onDisconnect` handler on `/vehicles/{driverUID}/isActive` to set it to `false` before writing any location data.
2. WHILE a Driver is streaming, THE LocationService SHALL write a `VehicleState` payload to `/vehicles/{driverUID}` in RTDB at every `POLL_INTERVAL_SECONDS` interval.
3. WHEN the device GPS returns a reading with `accuracy` greater than `MAX_ACCURACY_THRESHOLD`, THE LocationService SHALL skip that write cycle and wait for the next poll interval without writing to RTDB.
4. WHEN a Driver explicitly ends their streaming session, THE LocationService SHALL set `isActive` to `false` at `/vehicles/{driverUID}/isActive` in RTDB.
5. WHILE a Driver is streaming, THE LocationService SHALL ensure each successive `VehicleState` payload written to RTDB has a `timestamp` strictly greater than the `timestamp` of the previous payload.
6. WHEN the device GPS is unavailable for longer than `GPS_TIMEOUT_SECONDS`, THE LocationService SHALL display a warning to the Driver and pause streaming without writing stale or null data to RTDB.

---

### Requirement 4: Location Payload Construction

**User Story:** As a system, I want every location payload written to the database to be valid and complete, so that students always see accurate vehicle information.

#### Acceptance Criteria

1. WHEN `buildLocationPayload` is called with a valid `driverUID`, `routeId`, and `GeoPosition`, THE LocationService SHALL return a `VehicleState` with all fields (`vehicleId`, `driverName`, `routeId`, `latitude`, `longitude`, `accuracy`, `heading`, `speed`, `timestamp`, `isActive`) populated.
2. WHEN `buildLocationPayload` is called with a `latitude` outside the range [-90, 90], THE LocationService SHALL reject the payload and not write it to RTDB.
3. WHEN `buildLocationPayload` is called with a `longitude` outside the range [-180, 180], THE LocationService SHALL reject the payload and not write it to RTDB.
4. WHEN `buildLocationPayload` is called with an `accuracy` value that is zero or negative, THE LocationService SHALL reject the payload and not write it to RTDB.
5. THE LocationService SHALL set the `timestamp` field of every constructed `VehicleState` to the current wall-clock time in Unix epoch milliseconds at the moment of construction.
6. WHEN `buildLocationPayload` is called with a `routeId` that does not match any known route, THE LocationService SHALL reject the payload and not write it to RTDB.

---

### Requirement 5: Real-Time Vehicle Map View

**User Story:** As a student, I want to see all active E-Jeeps on a live map, so that I can decide when to go to a stop and which vehicle to board.

#### Acceptance Criteria

1. WHEN a Student opens the map view, THE VehicleDataListener SHALL subscribe to `/vehicles` in RTDB and deliver an initial snapshot of all vehicle data to the MapRenderer.
2. WHEN RTDB delivers a change event to the VehicleDataListener, THE MapRenderer SHALL update vehicle markers to reflect the new snapshot within one rendering frame.
3. WHEN a snapshot update is received, THE MapRenderer SHALL display a marker only for vehicles where `isActive = true` AND `isRecent(timestamp) = true`.
4. WHEN a snapshot update is received, THE MapRenderer SHALL remove the marker for any vehicle where `isActive = false` OR `isRecent(timestamp) = false`.
5. WHILE the map is displayed, THE MapRenderer SHALL maintain at most one marker per unique `vehicleId` at any time.
6. WHEN `onVehicleDataUpdate` is called with the same snapshot twice in succession, THE MapRenderer SHALL produce the same map marker state as if it had been called once (idempotent update).

---

### Requirement 6: Location Staleness Detection

**User Story:** As a student, I want the map to only show vehicles that are currently active, so that I am not misled by outdated location data.

#### Acceptance Criteria

1. WHEN `isRecent` is called with a `timestamp` where `(currentTimeMillis() - timestamp) ≤ STALE_THRESHOLD_MS`, THE System SHALL return `true`.
2. WHEN `isRecent` is called with a `timestamp` where `(currentTimeMillis() - timestamp) > STALE_THRESHOLD_MS`, THE System SHALL return `false`.
3. FOR ALL pairs of timestamps `t1` and `t2` where `t1 < t2`, IF `isRecent(t1) = true` THEN THE System SHALL also return `isRecent(t2) = true` (staleness monotonicity: more recent data is always at least as fresh as older data).
4. WHEN a vehicle's `timestamp` exceeds `STALE_THRESHOLD_MS`, THE MapRenderer SHALL remove that vehicle's marker from the map on the next snapshot processing cycle.

---

### Requirement 7: Offline and Disconnect Handling

**User Story:** As a student, I want the map to accurately reflect when a driver goes offline, so that I do not wait at a stop for a vehicle that is no longer running.

#### Acceptance Criteria

1. WHEN a Driver's network connection is lost, THE RTDB SHALL automatically execute the registered `onDisconnect` handler and set `/vehicles/{driverUID}/isActive` to `false`.
2. WHEN a Driver's `isActive` field is set to `false` by the `onDisconnect` handler, THE VehicleDataListener SHALL deliver the updated snapshot to the MapRenderer, which SHALL remove the vehicle's marker.
3. WHEN a Student's network connection is lost, THE VehicleDataListener SHALL pause updates and THE MapRenderer SHALL display a "Reconnecting…" status indicator to the Student.
4. WHEN a Student's network connection is restored, THE VehicleDataListener SHALL automatically reconnect to RTDB and deliver a fresh snapshot to the MapRenderer.
5. WHEN a Driver's network connection is restored after a drop, THE LocationService SHALL automatically resume streaming and set `isActive` to `true` on the next successful write.

---

### Requirement 8: Firebase Security Rules

**User Story:** As a system administrator, I want strict access controls on the database, so that only authorized drivers can write location data and students cannot tamper with vehicle records.

#### Acceptance Criteria

1. WHEN an authenticated Driver attempts to write to `/vehicles/{driverUID}` where `{driverUID}` matches their own Firebase Auth UID, THE RTDB Security Rules SHALL permit the write.
2. WHEN an authenticated Driver attempts to write to `/vehicles/{otherUID}` where `{otherUID}` does not match their own Firebase Auth UID, THE RTDB Security Rules SHALL deny the write.
3. WHEN an anonymous Student attempts to write to any path under `/vehicles`, THE RTDB Security Rules SHALL deny the write.
4. WHEN an anonymous Student attempts to read from `/vehicles`, THE RTDB Security Rules SHALL permit the read.
5. THE RTDB Security Rules SHALL deny all write access to `/vehicles` for unauthenticated (signed-out) clients.

---

### Requirement 9: Route Map Rendering

**User Story:** As a student, I want to see the E-Jeep routes drawn on the map, so that I can understand which vehicle serves my destination and where the stops are.

#### Acceptance Criteria

1. WHEN the map is initialized, THE MapRenderer SHALL render a GeoJSON polyline overlay for every route returned by `RouteDataService.loadRoutes()`.
2. WHEN rendering vehicle markers, THE MapRenderer SHALL color each marker using the `color` field of the `RouteGeoJSON` that matches the vehicle's `routeId`.
3. WHEN a vehicle's `routeId` does not match any known route, THE MapRenderer SHALL render that vehicle's marker using a default fallback marker style.
4. WHEN a Student taps a vehicle marker, THE MapRenderer SHALL display a popup containing the vehicle's `driverName`, `routeId`, and a human-readable representation of the `timestamp` (last updated time).
5. THE RouteDataService SHALL cache route GeoJSON data locally so that the route overlay renders correctly even when the device has no network connection.
6. WHEN `RouteDataService.loadRoutes()` is called, THE RouteDataService SHALL return the same set of routes regardless of whether the data is loaded from the network or the local cache.

---

### Requirement 10: Performance and Payload Constraints

**User Story:** As a system operator, I want the app to be efficient with network and battery resources, so that drivers can stream all day and students receive timely updates without excessive data usage.

#### Acceptance Criteria

1. THE LocationService SHALL default to a `POLL_INTERVAL_SECONDS` of 3 seconds for GPS writes.
2. WHEN a Driver's speed is below a low-speed threshold (e.g., stationary detection), THE LocationService SHALL allow the poll interval to be increased to 5 seconds to conserve battery.
3. THE LocationService SHALL construct each `VehicleState` payload such that its serialized size does not exceed 500 bytes.
4. WHEN updating a vehicle marker position, THE MapRenderer SHALL move the existing marker in place rather than removing and recreating it, to prevent map flicker.
5. WHILE the Driver app is in the foreground, THE LocationService SHALL use the platform's high-accuracy location mode.
6. WHILE the Driver app is in the background, THE LocationService SHALL use the platform's balanced-power location mode to reduce battery consumption.

---

### Requirement 11: Driver Account Management

**User Story:** As a UST transport office administrator, I want to control which drivers can use the app, so that only authorized E-Jeep operators can stream location data.

#### Acceptance Criteria

1. THE AuthService SHALL only permit sign-in for Driver accounts that have been provisioned by an administrator.
2. WHEN a Driver account is deprovisioned, THE AuthService SHALL prevent that account from authenticating and streaming location data.
3. THE System SHALL store full Driver profile information (contact details, plate number) in Firestore with access rules separate from the RTDB `/vehicles` node.
4. THE System SHALL NOT store personally identifiable Driver information (beyond `driverName`) in the RTDB `/vehicles` node.

---

### Requirement 12: Authentication Token Management

**User Story:** As a driver, I want my session to remain active during my shift without interruption, so that I do not have to re-authenticate while on duty.

#### Acceptance Criteria

1. THE AuthService SHALL silently refresh the Firebase Auth token before it expires (tokens expire after 1 hour) without interrupting the Driver's streaming session.
2. WHEN a token refresh fails, THE AuthService SHALL prompt the Driver to re-authenticate and pause location streaming until a valid token is obtained.
3. WHEN a Driver signs out, THE AuthService SHALL invalidate the local session and THE LocationService SHALL stop streaming immediately.
