# Non-Blocking Location Update Delivery

Implemented non-blocking handling for own-location uploads when a direct `UpdateLocation` request hangs.

- Treats an in-flight direct upload as the logical FIFO head.
- Queues later location submissions immediately instead of waiting for the active network request.
- Restores a retryable failed direct upload to the front of the outbox before later queued samples.
- Blocks flushes from bypassing the in-flight or restoring direct-send head.
- Replays an in-flight direct upload to the new server URL after retargeting, preserving existing server-change behavior.
- Changes Core Location batch upload handoff so accepted samples reach the coordinator promptly.
- Adds Miataru API client request/resource timeouts.
- Adds focused coordinator regression tests and updates the test catalog/gap matrix.
- Updates the changelog for version 3.3.2.

Validation:

- `cd miataru && ./scripts/test-unit.sh -only-testing:miataruTests/LocationUpdateDeliveryCoordinatorTests`
- `cd miataru && ./scripts/test-unit.sh`
- `git diff --check`
