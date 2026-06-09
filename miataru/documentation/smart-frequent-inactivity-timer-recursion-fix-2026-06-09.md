# Smart Frequent Inactivity Timer Recursion Fix

Date: 2026-06-09

## Summary

A diagnostics export and crash stack showed that entering background could enter a synchronous recursion between `scheduleSmartFrequentBackgroundInactivityTimer` and `handleSmartFrequentBackgroundInactivityIfNeeded`. The crash path appeared after switching the frequent distance filter from 100 m to 25 m, but the underlying failure was the stale callback gap state in Smart frequent runtime.

The problematic state was:

- Smart frequent runtime was still active.
- `lastRelevantMovementAt + inactivityWindow` was already in the past.
- `lastLocationUpdateAt` was stale enough that `shouldDeactivate` intentionally returned `false`, because missing frequent callbacks are watchdog recovery cases, not proof of stillness.
- The old scheduler treated the past inactivity timeout as immediately due, called the handler synchronously, and the handler scheduled the same immediately due timeout again.

That loop repeatedly touched published state and surfaced in SwiftUI transaction frames near the top of the crash stack.

## Behavior

`SmartFrequentBackgroundPolicy` now exposes `InactivityTimerAction`:

- `.schedule(Date)` when callback data is fresh and the inactivity timeout is still in the future.
- `.expired` when callback data is fresh and relevant movement has already aged out.
- `.none` when timestamps are missing, the inactivity window is invalid, or the callback gap is stale.

`LocationManager.scheduleSmartFrequentBackgroundInactivityTimer` uses that action directly instead of deriving an immediate handler call from a past date. Stale callback gaps clear `smartFrequentBackgroundNextInactivityTimeoutAt` and leave recovery to the Smart frequent watchdog. Expired but fresh inactivity is evaluated at most once in the scheduler path.

The public `nextInactivityTimeout` helper keeps its original date-only semantics for existing tests and compatibility wrappers. The new action helper owns the `now`-dependent decision that decides whether an inactivity timer should actually be scheduled or evaluated.

## Diagnostics

When a stale callback gap prevents inactivity evaluation, Location Diagnostics records a coalesced info event:

- `event`: `smartFrequentInactivityTimer`
- `result`: `notScheduled`
- `reason`: `stale callback gap prevents inactivity evaluation`

The context includes the last callback timestamp, last relevant movement timestamp, their ages, the inactivity window, and the Smart runtime phase. This makes the crash-prevention path visible without flooding the diagnostics ring buffer.

## 25 m Accuracy Note

This fix does not change frequent background accuracy acceptance. The gate remains:

```text
horizontalAccuracy <= max(configuredFrequentDistanceFilter, 50 m)
```

That means 25 m mode accepts fixes up to 50 m accuracy and rejects a 69.4 m frequent-background fix. The new regression test documents that stricter 25 m behavior separately from the inactivity-timer crash fix.

## Validation

Verified locally on the `miataru` scheme:

- `SmartFrequentBackgroundPolicyTests`: 10 tests passed.
- `LocationTrackingPolicyTests`: 13 tests passed.
- Full test run: 192 Swift Testing/unit tests plus 6 `ExtendedUITests` passed.
