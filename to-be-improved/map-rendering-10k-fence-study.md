# Map Rendering Performance Study for ~10K Fences

_Date: 2025-10-10_

## Context

The current SwiftUI-based map rendering strategy in `NetworkCoverageViewModel` and `FencesMapView` was tuned for hundreds of fences. We need to anticipate scenarios where coverage history contains **≈10,000 fence points** representing long-running drive tests. This document evaluates the theoretical impact on CPU, memory, and UI responsiveness, and outlines mitigation strategies.

---

## Current Pipeline (recap)

1. **Raw fences** (`[Fence]`) arrive via history detail or live measurement.
2. `fenceItems` is rebuilt by mapping every `Fence` to `FenceItem` (one `UUID`, coordinate, color, selection flags).
3. `updateRenderedFences()` derives:
   - `visibleFenceItems` (optionally culled to the map region).
   - `fencePolylineSegments` (grouped by technology, deterministic IDs).
   - `mapRenderMode` (switches to polylines when thresholds are crossed).
4. SwiftUI re-renders `FencesMapView` with these arrays.

Key data structures scale linearly with the number of fences.

---

## Expected Performance with 10K Fences

### CPU

- **Mapping to `FenceItem`**: O(n). For 10K items, this is acceptable (~0.3–0.6 ms per 1K elements on modern devices) but will spike if repeated frequently. The current code remaps on every fence mutation (e.g. while measuring live). For history detail (single load) it is fine; for live tracking it could become a hotspot.
- **Polyline construction**: also O(n). With 10K points, grouping per technology requires scanning the entire list even if only a few items changed. If map updates arrive often, this introduces frame drops.
- **Culling**: `filteredFenceItems` iterates over the full array; `filteredPolylineSegments` checks every coordinate inside each segment. Long segments (hundreds of points) magnify the cost.

### Memory

- Each `FenceItem` stores coordinate, color, flags (~80–96 bytes). Ten thousand items ⇒ ~1 MB. Add duplicate arrays (`visibleFenceItems` and polyline coordinates) and memory could reach 3–4 MB. This is acceptable, but constant remapping increases allocations and ARC churn.

### SwiftUI/MapKit

- Circles mode caps at `maxCircleCountBeforePolyline` (60 by default), so we avoid 10K circle overlays. However, polylines still carry up to 10K coordinates. `MapPolyline` renders efficiently but culling needs to ensure we do not attempt to draw far-off segments.
- `@State` updates trigger SwiftUI diffing. Large array replacements (10K elements) cause diffing overhead. Our deterministic IDs help, but repeated `visibleFenceItems = filtered` clones still require SwiftUI to walk long arrays.

### Summary of Bottlenecks

| Area | Impact at 10K fences | Notes |
| --- | --- | --- |
| Mapping `Fence` → `FenceItem` | Medium | Recomputed wholesale on mutations. |
| Polyline generation | High | Linear scan per update; segments may still retain all coordinates. |
| Culling | Medium/High | Filters arrays by iterating every item and coordinate; lacks bounding boxes. |
| SwiftUI diffing | Medium | Large array replacements, though IDs mitigate worst case. |
| Memory | Low/Medium | ~3–4 MB overhead but manageable. |

---

## Recommended Mitigations

1. **Incremental Mapping Cache**
   - Store a dictionary `id → FenceItem` and only update items whose source fences changed. This keeps `fenceItems` updates O(k) where k is the number of modified fences (often 1 during live measurement).

2. **Segment Builder Optimisation**
   - Maintain segments incrementally: when new fences arrive, append to the last segment or create a new segment instead of rebuilding the entire array. For history detail (static), keep the current build path but run it once on a background queue.

3. **Precomputed Bounding Boxes**
   - Extend `FencePolylineSegment` with `boundingBox`. Filtering then becomes:
     ```swift
     guard boundingBox.intersects(paddedRegionBox) else skip
     ```
     Only if boxes intersect do we inspect individual coordinates.

4. **Region-Based Bucketing**
   - Pre-bucket fences (e.g. geohash or quad-tree) so `filteredFenceItems` retrieves only relevant buckets, reducing per-frame loops.

5. **Async Rendering Preparation**
   - Perform heavy computations (`buildPolylineSegments`, initial culling) off the main actor using structured concurrency (`Task.detached`) and publish results back on the main actor, ensuring UI remains responsive.

6. **Streaming Polylines**
   - For extremely long paths, decimate coordinates (Douglas–Peucker) when zoomed out. Keep original fidelity for zoomed-in spans by recalculating using the live zoom level.

7. **Mutable Storage**
   - Replace repeated array assignments with mutable storage objects (e.g. `class RenderState { var segments: [FencePolylineSegment] }`) so SwiftUI sees small updates (`Observable` changes) instead of wholesale array copies.

---

## Investigation Notes

- Thresholds currently switch to polylines when both `items.count >= 60` and `max(span) ≥ 0.03`. For 10K points, the switch happens immediately, keeping circle overlays bounded.
- Deterministic segment IDs (`technology|UUID:UUID`) remain stable even with incremental updates, so any caching strategy must preserve this formation.
- Culling factor (`visibleRegionPaddingFactor = 1.2`) offers a 20% buffer. For 10K fences stretched across a country, consider adaptive padding based on zoom to avoid retaining thousands of coordinates unnecessarily.

---

## Next Steps (When Performance Work Is Prioritised)

1. Profile with synthetic 10K fence data using Instruments (`Time Profiler` and `Allocations`) to confirm the theoretical hotspots.
2. Implement incremental mapping + segment caching behind feature flags so behaviour parity can be validated with existing tests.
3. Add benchmark tests (e.g. Measure Swift macro or XCT performance tests) to guard future regressions.

---

*Prepared by: Codex (GPT-5)
*
