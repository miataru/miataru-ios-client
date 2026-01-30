---
name: GhostSpeedIncorporation
overview: Incorporate available device/user speeds into the ghost position projection along the route line using the faster available speed, while keeping fallbacks.
todos:
  - id: calc-update
    content: Extend RouteGhostCalculator to use fastest available speed
    status: completed
  - id: view-wire
    content: Pass user and device speeds/timestamps to ghost call
    status: completed
    dependencies:
      - calc-update
  - id: verify-render
    content: Sanity check ghost/progress rendering with fallbacks
    status: completed
    dependencies:
      - view-wire
---

# Incorporate

speed into ghost projection

- Update [`miataru/views/Common/Map/RouteGhostCalculator.swift`](miataru/views/Common/Map/RouteGhostCalculator.swift) to accept optional speeds/timestamps for both devices, pick the fastest speed above the threshold, and compute distance progressed accordingly (fallback to expected travel time when no usable speed).