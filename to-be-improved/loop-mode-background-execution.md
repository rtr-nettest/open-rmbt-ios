# Loop Mode Background Execution: Corrected Constraints, Reliable Plan, and Experiment Path

## Goal

Determine whether Loop Mode can run reliably when the app goes to background, and define:

1. A production-safe solution.
2. A low-effort experiment to measure real background degradation in the current implementation.

---

## Executive Summary

- Full Loop Mode throughput tests in background are **not reliably supportable** on iOS with this architecture.
- Trying to force it via unrelated background modes (for example `voip`) is **not acceptable** and is App Review risk.
- The production-safe design is:
  - **Foreground only:** ping/download/upload/QoS execution.
  - **Background allowed:** waiting/orchestration only (time/distance progress + notification).
- If we still want data, we can add a **debug-only best-effort experiment mode** that disables current background cancellation and logs quality/failure deltas.

---

## What Is Confirmed in Current Code

### 1) Active test is cancelled when app backgrounds

`Sources/RMBTTestRunner.swift`

```swift
@objc func applicationDidSwitchToBackground(_ notification: Notification) {
    Log.logger.error("App backgrounded, aborting \(notification)")
    workerQueue.async {
        self.cancel(with: .appBackgrounded)
    }
}
```

### 2) Loop can transition to waiting after cancel

`Sources/Test/RMBTTestViewController.swift`

- `onTestCancelled(with:)` moves to waiting for non-user cancellation in loop mode.

### 3) Waiting currently depends on components that stop when app backgrounds

`Sources/Test/RMBTTestViewController.swift`

- Waiting time uses a repeating timer (`startWaitingNextTest`, `tick`).
- Distance uses `RMBTLocationTracker` callbacks.

`Sources/RMBTAppDelegate.swift`

```swift
func applicationDidEnterBackground(_ application: UIApplication) {
    RMBTLocationTracker.shared.stop()
    NetworkReachability.shared.stopMonitoring()
}
```

This means current waiting logic does not continue while app is suspended.

### 4) Throughput engine is long-lived socket + worker driven

`Sources/RMBTTestWorker.swift`

- Uses `CocoaAsyncSocket` (`GCDAsyncSocket`) and multi-phase timing-sensitive flow.

This is not an opportunistic transfer model.

---

## Corrected Platform Constraints

### A) No background mode gives foreground-equivalent continuous throughput testing

- iOS can suspend/deprioritize app execution in background.
- Background transfer APIs (`URLSession` background) are optimized for delivery, not benchmark fidelity.

### B) You cannot periodically force app into foreground

- iOS requires user intent to bring UI foreground.
- App can be resumed in background by system mechanisms, but cannot self-launch to active UI on a timer.

### C) `voip` is not a valid workaround

- `voip` mode is for real call flows and is tightly enforced.
- Using it to keep speed tests alive is policy and review risk.

---

## Assumptions in Previous Proposal That Need Correction

1. "Ready notification exactly at threshold without active process" is guaranteed.
- Not guaranteed unless notification is scheduled explicitly (time-based trigger), and distance threshold events still depend on background location delivery.

2. `RealLocationUpdatesService().locations()` can be created directly.
- Current type requires injected closures (`now`, `canReportLocations`).

3. Background capability is always present.
- `Scripts/update_configurations_from_private.sh` copies either private or public plist into `Resources/RMBT-Info.plist`.
- `public/Configurations/RMBT-Info.plist` currently does not include `UIBackgroundModes=location`.
- Therefore behavior depends on which configuration is active.

4. Background waiting can always be started after app is already in background.
- Lifecycle details matter; session/setup timing must be designed carefully.

---

## Production Recommendation (Reliable)

### Option A (recommended): Foreground tests + background waiting

### Behavior

- Test starts in foreground.
- If app backgrounds during active test: cancel test (current behavior stays).
- Loop enters waiting state.
- Waiting can progress in background using:
  - persisted start timestamp for time condition,
  - location updates for distance condition when available,
  - local notification when next test becomes eligible.
- Next test starts only after app returns foreground.

### Pros

- Best App Review posture.
- Preserves measurement integrity (no forced background throughput).
- Minimal architecture risk.

### Cons

- User must return to app for each test run.

---

### Option B (best effort, not production default): allow active test in background

### Behavior

- Do not cancel active test immediately on background.
- Attempt to continue until suspension/expiration/failure.

### Pros

- Allows empirical measurement of degradation.

### Cons

- Not reliable by design.
- App Review risk if shipped as user-facing promise.
- Results may be biased by background scheduling and suspension timing.

Use only behind debug/feature flag for internal study.

---

## Rejected Paths

- Misusing unrelated background modes (`voip`, audio, etc.) to keep networking alive.
- Claiming "continuous background Loop Mode" as guaranteed product behavior.

---

## Minimal Experiment Plan (Low Effort, Current Architecture)

Goal: quantify whether background degradation is severe in practice for your real users/networks.

### Experiment Mode: smallest code surface

### Change 1: add debug flag

- Add `debugLoopModeAllowBackgroundBestEffort` in `RMBTSettings` (debug-only behavior).

### Change 2: conditional cancel in runner

`Sources/RMBTTestRunner.swift`

- In `applicationDidSwitchToBackground`:
  - if flag is `false`: keep current cancel behavior.
  - if flag is `true`: do not cancel, only log transition timestamp and phase.

### Change 3: keep location tracker alive only in experiment path

`Sources/RMBTAppDelegate.swift`

- In `applicationDidEnterBackground`, conditionally skip `RMBTLocationTracker.shared.stop()` only when:
  - experiment flag is enabled,
  - and loop measurement is active (`RMBTSettings.shared.activeMeasurementId` set).

This gives best chance to keep process active in background without broad redesign.

### Change 4: add structured telemetry (must-have)

For each test result, record at minimum:

- `started_in_state`: foreground/background.
- `did_background_during_test`: bool.
- `background_entry_phase`: ping/down/up/qos.
- `background_duration_while_test_active_s`.
- `cancel_reason`.
- `bytes_uploaded`, `bytes_downloaded`, phase durations.
- final throughput/ping values.

Without this, experiment results are not interpretable.

---

## How to Evaluate "Good Enough"

Use paired runs on same route/time window:

1. Foreground baseline set.
2. Experiment best-effort background set.

Compare:

- success rate drop (percentage points),
- median down/up degradation (%),
- p95 degradation,
- increased cancellations/timeouts.

Suggested provisional acceptance threshold for "usable":

- success rate drop <= 5 percentage points,
- median throughput degradation <= 10%,
- p95 degradation <= 25%.

If outside this, background execution is not good enough for production measurement claims.

---

## Practical Implementation Sequence

1. Implement Option A (production-safe waiting in BG).
2. Add Option B experiment flag (debug-only).
3. Run internal test matrix for at least:
   - LTE/5G, Wi-Fi, mixed mobility,
   - 30+ paired samples per scenario.
4. Decide product behavior from evidence.

---

## Notes About Configuration

Because build-time script swaps plist/config files, confirm active config before validating background behavior:

- `Scripts/update_configurations_from_private.sh`
- `private/Configurations/RMBT-Info.plist`
- `public/Configurations/RMBT-Info.plist`
- `Resources/RMBT-Info.plist` (effective copied target)

Background location expectations are invalid if active plist does not include location background mode.

---

## Final Answer to Original Question

- Can Loop Mode run reliably in background with no meaningful network degradation? **No (not as a guaranteed product behavior).**
- Can we still test whether it is "good enough" in practice? **Yes**, with a debug-only best-effort mode and proper telemetry.
- Can app periodically wake itself to foreground without user action? **No.**
