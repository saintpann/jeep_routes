/**
 * Geo-utility functions for the UST E-Jeep Transit App ETA Cloud Function.
 *
 * All coordinate conventions follow GeoJSON: [longitude, latitude] pairs.
 * Haversine distances are returned in metres.
 */

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface RouteProgress {
  projectedLatitude: number;
  projectedLongitude: number;
  distanceTravelledM: number;
  totalRouteLengthM: number;
  /** Always clamped to [0, 1]. */
  progressFraction: number;
}

// ---------------------------------------------------------------------------
// haversineDistance
// ---------------------------------------------------------------------------

/**
 * Returns the great-circle distance in metres between two WGS-84 points.
 *
 * Uses the standard haversine formula with Earth radius = 6 371 000 m.
 */
export function haversineDistance(
  lat1: number,
  lng1: number,
  lat2: number,
  lng2: number,
): number {
  const R = 6_371_000; // Earth radius in metres

  const toRad = (deg: number) => (deg * Math.PI) / 180;

  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);

  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(toRad(lat1)) *
      Math.cos(toRad(lat2)) *
      Math.sin(dLng / 2) *
      Math.sin(dLng / 2);

  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));

  return R * c;
}

// ---------------------------------------------------------------------------
// closestPointOnSegment
// ---------------------------------------------------------------------------

/**
 * Returns the closest point on the line segment [A, B] to point P.
 *
 * All coordinates are [longitude, latitude] pairs (GeoJSON convention).
 * The returned point is expressed as `{ lat, lng }`.
 *
 * Uses vector projection; parameter `t` is clamped to [0, 1] so the result
 * always lies on the segment (never on the extended line).
 */
export function closestPointOnSegment(
  px: number,
  py: number,
  ax: number,
  ay: number,
  bx: number,
  by: number,
): { lat: number; lng: number } {
  const abx = bx - ax;
  const aby = by - ay;

  const lenSq = abx * abx + aby * aby;

  if (lenSq === 0) {
    // Degenerate segment — A and B are the same point.
    return { lat: ay, lng: ax };
  }

  // Project P onto the line through A and B.
  const t = ((px - ax) * abx + (py - ay) * aby) / lenSq;

  // Clamp t to [0, 1] so the result stays on the segment.
  const tClamped = Math.max(0, Math.min(1, t));

  return {
    lat: ay + tClamped * aby,
    lng: ax + tClamped * abx,
  };
}

// ---------------------------------------------------------------------------
// projectOntoRoute
// ---------------------------------------------------------------------------

/**
 * Projects the point (latitude, longitude) onto the nearest segment of the
 * route polyline and returns a {@link RouteProgress} describing how far along
 * the route the projected point lies.
 *
 * @param latitude  - WGS-84 latitude of the point to project.
 * @param longitude - WGS-84 longitude of the point to project.
 * @param coordinates - GeoJSON LineString coordinate array: each element is
 *   `[longitude, latitude]`.
 *
 * Preconditions:
 *   - `coordinates.length >= 2`
 *   - `latitude ∈ [-90, 90]`, `longitude ∈ [-180, 180]`
 *
 * Postconditions:
 *   - `progressFraction ∈ [0, 1]`
 *   - `distanceTravelledM ≤ totalRouteLengthM`
 */
export function projectOntoRoute(
  latitude: number,
  longitude: number,
  coordinates: number[][],
): RouteProgress {
  let minDistanceM = Infinity;
  let bestSegmentIndex = 0;
  let bestProjectedLat = latitude;
  let bestProjectedLng = longitude;
  let totalRouteLengthM = 0;

  // ── Pass 1: find the nearest segment and accumulate total route length ──
  for (let i = 0; i < coordinates.length - 1; i++) {
    const [ax, ay] = coordinates[i];     // [lng, lat]
    const [bx, by] = coordinates[i + 1]; // [lng, lat]

    const projected = closestPointOnSegment(longitude, latitude, ax, ay, bx, by);
    const distToProjected = haversineDistance(
      latitude,
      longitude,
      projected.lat,
      projected.lng,
    );

    if (distToProjected < minDistanceM) {
      minDistanceM = distToProjected;
      bestSegmentIndex = i;
      bestProjectedLat = projected.lat;
      bestProjectedLng = projected.lng;
    }

    totalRouteLengthM += haversineDistance(ay, ax, by, bx);
  }

  // ── Pass 2: sum segment lengths up to (but not including) the best segment ──
  let distanceTravelledM = 0;

  for (let i = 0; i < bestSegmentIndex; i++) {
    const [ax, ay] = coordinates[i];
    const [bx, by] = coordinates[i + 1];
    distanceTravelledM += haversineDistance(ay, ax, by, bx);
  }

  // ── Add partial distance within the best segment ──
  const [segStartLng, segStartLat] = coordinates[bestSegmentIndex];
  distanceTravelledM += haversineDistance(
    segStartLat,
    segStartLng,
    bestProjectedLat,
    bestProjectedLng,
  );

  // ── Compute and clamp progressFraction ──
  const progressFraction =
    totalRouteLengthM > 0
      ? Math.max(0, Math.min(1, distanceTravelledM / totalRouteLengthM))
      : 0;

  return {
    projectedLatitude: bestProjectedLat,
    projectedLongitude: bestProjectedLng,
    distanceTravelledM,
    totalRouteLengthM,
    progressFraction,
  };
}
