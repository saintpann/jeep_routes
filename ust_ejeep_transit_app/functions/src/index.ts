import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';
import { projectOntoRoute } from './geo_utils';

admin.initializeApp();

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const STALE_THRESHOLD_MS = 30_000;          // 30 seconds
const DEFAULT_SPEED_MPS = 5.56;             // ~20 km/h fallback

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

interface VehicleState {
  vehicleId: string;
  driverName: string;
  routeId: string;
  latitude: number;
  longitude: number;
  accuracy: number;
  heading: number;
  speed: number;       // km/h
  timestamp: number;   // epoch ms
  isActive: boolean;
}

interface Stop {
  stopId: string;
  name: string;
  latitude: number;
  longitude: number;
  sequence: number;
}

interface RouteData {
  routeId: string;
  routeName: string;
  color: string;
  geometry: number[][];  // [lng, lat] pairs
  stops: Stop[];
}

// ---------------------------------------------------------------------------
// Hardcoded route data (mirrors assets/routes.geojson)
// ---------------------------------------------------------------------------

const ROUTES: RouteData[] = [
  {
    routeId: 'route-espana-quiapo',
    routeName: 'UST – España – Quiapo',
    color: '#2196F3',
    geometry: [
      [120.9897, 14.6097],
      [120.9885, 14.6090],
      [120.9870, 14.6082],
      [120.9862, 14.6078],
      [120.9850, 14.6068],
      [120.9840, 14.6058],
      [120.9830, 14.6055],
      [120.9818, 14.6045],
      [120.9808, 14.6035],
      [120.9800, 14.6030],
      [120.9810, 14.6015],
      [120.9820, 14.6000],
      [120.9835, 14.5990],
      [120.9840, 14.5985],
    ],
    stops: [
      {
        stopId: 'stop-ust-gate-1',
        name: 'UST Gate 1 (España Blvd)',
        latitude: 14.6097,
        longitude: 120.9897,
        sequence: 1,
      },
      {
        stopId: 'stop-espana-lacson',
        name: 'España – Lacson Intersection',
        latitude: 14.6078,
        longitude: 120.9862,
        sequence: 2,
      },
      {
        stopId: 'stop-espana-g-tuazon',
        name: 'España – G. Tuazon',
        latitude: 14.6055,
        longitude: 120.9830,
        sequence: 3,
      },
      {
        stopId: 'stop-espana-quezon',
        name: 'España – Quezon Blvd',
        latitude: 14.6030,
        longitude: 120.9800,
        sequence: 4,
      },
      {
        stopId: 'stop-quiapo-church',
        name: 'Quiapo Church',
        latitude: 14.5985,
        longitude: 120.9840,
        sequence: 5,
      },
    ],
  },
  {
    routeId: 'route-lacson-sampaloc',
    routeName: 'UST – Lacson – Sampaloc',
    color: '#4CAF50',
    geometry: [
      [120.9880, 14.6110],
      [120.9875, 14.6118],
      [120.9870, 14.6125],
      [120.9865, 14.6135],
      [120.9860, 14.6143],
      [120.9855, 14.6150],
      [120.9850, 14.6160],
      [120.9845, 14.6168],
      [120.9840, 14.6175],
      [120.9835, 14.6185],
      [120.9828, 14.6193],
      [120.9822, 14.6200],
      [120.9820, 14.6210],
    ],
    stops: [
      {
        stopId: 'stop-ust-lacson-gate',
        name: 'UST Lacson Gate',
        latitude: 14.6110,
        longitude: 120.9880,
        sequence: 1,
      },
      {
        stopId: 'stop-lacson-dapitan',
        name: 'Lacson – Dapitan',
        latitude: 14.6135,
        longitude: 120.9865,
        sequence: 2,
      },
      {
        stopId: 'stop-lacson-earnshaw',
        name: 'Lacson – Earnshaw',
        latitude: 14.6160,
        longitude: 120.9850,
        sequence: 3,
      },
      {
        stopId: 'stop-sampaloc-market',
        name: 'Sampaloc Market',
        latitude: 14.6185,
        longitude: 120.9835,
        sequence: 4,
      },
      {
        stopId: 'stop-lacson-aurora',
        name: 'Lacson – Aurora Blvd',
        latitude: 14.6210,
        longitude: 120.9820,
        sequence: 5,
      },
    ],
  },
];

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function isRecent(timestamp: number): boolean {
  return Date.now() - timestamp <= STALE_THRESHOLD_MS;
}

function findRoute(routeId: string): RouteData | undefined {
  return ROUTES.find((r) => r.routeId === routeId);
}

function findStop(route: RouteData, stopId: string): Stop | undefined {
  return route.stops.find((s) => s.stopId === stopId);
}

// ---------------------------------------------------------------------------
// calculateETA — HTTPS Callable Cloud Function
// ---------------------------------------------------------------------------

export const calculateETA = functions.https.onCall(async (data, _context) => {
  // ── Step 1: Validate input ──────────────────────────────────────────────
  const { vehicleId, stopId, routeId } = data as {
    vehicleId?: string;
    stopId?: string;
    routeId?: string;
  };

  if (!vehicleId || !stopId || !routeId) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'vehicleId, stopId, and routeId are required.',
    );
  }

  // ── Step 2: Fetch vehicle from RTDB ────────────────────────────────────
  const vehicleSnap = await admin
    .database()
    .ref('vehicles/' + vehicleId)
    .once('value');

  const vehicle = vehicleSnap.val() as VehicleState | null;

  if (!vehicle || !vehicle.isActive) {
    return { status: 'unavailable', reason: 'VEHICLE_INACTIVE' };
  }

  if (!isRecent(vehicle.timestamp)) {
    return { status: 'unavailable', reason: 'STALE_POSITION' };
  }

  // ── Step 3: Resolve route ───────────────────────────────────────────────
  const route = findRoute(routeId);
  if (!route) {
    return { status: 'unavailable', reason: 'UNKNOWN_ROUTE' };
  }

  // ── Step 4: Resolve stop ────────────────────────────────────────────────
  const stop = findStop(route, stopId);
  if (!stop) {
    return { status: 'unavailable', reason: 'UNKNOWN_STOP' };
  }

  // ── Step 5: Project vehicle and stop onto route ─────────────────────────
  const vehicleProgress = projectOntoRoute(
    vehicle.latitude,
    vehicle.longitude,
    route.geometry,
  );

  const stopProgress = projectOntoRoute(
    stop.latitude,
    stop.longitude,
    route.geometry,
  );

  // ── Step 6: Check if stop has already been passed ───────────────────────
  if (stopProgress.distanceTravelledM <= vehicleProgress.distanceTravelledM) {
    return { status: 'unavailable', reason: 'STOP_PASSED' };
  }

  // ── Step 7: Compute remaining distance and ETA ──────────────────────────
  const remainingDistanceM =
    stopProgress.distanceTravelledM - vehicleProgress.distanceTravelledM;

  const effectiveSpeedMps =
    vehicle.speed > 0 ? vehicle.speed / 3.6 : DEFAULT_SPEED_MPS;

  const estimatedArrivalSec = Math.max(
    0,
    Math.round(remainingDistanceM / effectiveSpeedMps),
  );

  // ── Step 8: Determine confidence level ─────────────────────────────────
  const positionAgeMs = Date.now() - vehicle.timestamp;

  let confidence: string;
  if (vehicle.speed > 0 && positionAgeMs < 10_000) {
    confidence = 'high';
  } else if (positionAgeMs < 10_000) {
    confidence = 'medium';
  } else {
    confidence = 'low';
  }

  // ── Step 9: Return result ───────────────────────────────────────────────
  return {
    status: 'available',
    vehicleId,
    stopId,
    routeId,
    estimatedArrivalSec,
    distanceRemainingM: remainingDistanceM,
    confidence,
    computedAt: Date.now(),
  };
});
