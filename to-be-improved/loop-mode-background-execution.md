# Loop Mode Background Execution: Constraints and Solutions

## Overview

Loop Mode performs repeated network speed tests with configurable waiting periods between tests (time-based and/or distance-based). Unlike Network Coverage, which measures lightweight pings continuously, Loop Mode runs full throughput tests (ping, download, upload, QoS) that involve sustained multi-threaded socket I/O. This document explains why Loop Mode tests cannot run in the background and proposes a minimal, App Review-compliant solution that allows the waiting period to progress while backgrounded.

---

## Why Loop Mode Tests Cannot Run in Background

### 1. Technical Constraints: Socket Connection Lifecycle

Loop Mode's measurement architecture (`RMBTTestRunner`, `RMBTTestWorker`) relies on:

- **CocoaAsyncSocket** for TCP connections to measurement servers
- **Multiple parallel worker threads** (typically 3–4) for concurrent downloads/uploads
- **Sustained high-bandwidth transfers** lasting 7–10 seconds per phase
- **Stateful socket connections** that must remain open throughout measurement

| Aspect | Foreground | Background (even with `CLBackgroundActivitySession`) |
|--------|------------|------------------------------------------------------|
| Socket lifecycle | Full control; connections persist | iOS throttles/tears down connections |
| Thread scheduling | Workers run continuously | Threads suspended or deprioritized |
| Bandwidth allocation | Full radio budget | Duty-cycled; throttled to save power |
| Test reliability | High | **Low: frequent failures, corrupted results** |

**Technical reality:** iOS routinely terminates or throttles long-running socket connections in the background, even when an app holds `CLBackgroundActivitySession`. Background modes are designed for lightweight tasks (location updates, small network requests), not sustained throughput measurements.

### 2. App Store Policy: Abuse of Background Location

The app already declares `UIBackgroundModes = ["location"]` for Network Coverage, which is legitimate because:

- **Primary purpose:** Location tracking (WHERE the user is)
- **Secondary network activity:** Small ICMP pings (~64 bytes, periodic)
- **Intent alignment:** Measuring cellular coverage at different locations

If Loop Mode were to run speed tests in the background:

- **Primary purpose:** Network throughput testing (NOT location-based)
- **Network activity:** Megabytes of sustained TCP transfers
- **Intent mismatch:** Using location mode as a loophole to run bandwidth tests

**App Review risk:** Apple rejects apps that abuse background location for non-location purposes. Running multi-megabyte speed tests while claiming "location-based service" is a clear violation.

### 3. Comparison to Network Coverage

| Feature | Network Coverage | Loop Mode Speed Tests |
|---------|------------------|----------------------|
| **Network load** | ~64 bytes per ping, every 2s | Megabytes per test, sustained |
| **Connection type** | UDP (connectionless) | TCP (stateful, multi-threaded) |
| **Duration** | Continuous background OK | 7–10s bursts, foreground only |
| **iOS compatibility** | ✅ Works with `CLBackgroundActivitySession` | ❌ iOS kills sockets |
| **App Review legitimacy** | ✅ Location-based service | ❌ Network testing disguised as location |

**Key insight:** The Network Coverage implementation (Sources/NetworkCoverage/) cannot be directly applied to Loop Mode because the underlying workload is fundamentally different.

---

## Current Behavior (Foreground-Only)

### Implementation (Sources/RMBTTestRunner.swift:568-573)

```swift
@objc func applicationDidSwitchToBackground(_ notification: Notification) {
    Log.logger.error("App backgrounded, aborting \(notification)")
    workerQueue.async {
        self.cancel(with: .appBackgrounded)
    }
}
```

When the app backgrounds during a Loop Mode test:

1. **Active test cancelled** (Sources/RMBTTestRunner.swift:259-287)
2. **TestViewController handles cancellation** (Sources/Test/RMBTTestViewController.swift:802-807)
3. **Loop session transitions to waiting state** (already implemented, line 805)
4. **Waiting logic uses timers/location tracker** (RMBTTestViewController.swift:569-620)
   - Timer runs every 0.3s to check time elapsed (line 589)
   - Location tracker monitors distance traveled (line 592-620)
   - **Problem:** Timers don't fire when app is suspended; location tracker is stopped by AppDelegate

### Why Waiting Fails in Background

From RMBTAppDelegate.swift:

```swift
func applicationDidEnterBackground(_ application: UIApplication) {
    RMBTLocationTracker.shared.stop()  // ← Stops location updates
    NetworkReachability.shared.stopMonitoring()
}
```

From RMBTTestViewController.swift:

```swift
private func startWaitingNextTest() {
    // ← Timer-based waiting: won't run while suspended
    timer = Timer.scheduledTimer(timeInterval: 0.3, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
}
```

**Result:** When app backgrounds during waiting, both time and distance tracking stop. User must keep app in foreground for entire loop duration.

---

## Proposed Solution: Background Waiting (Tests Remain Foreground-Only)

### Strategy

1. **Tests run in foreground only** (keep existing cancellation behavior)
2. **Waiting period continues in background**
   - Time-based: Compute elapsed on resume (no active timer)
   - Distance-based: Subscribe to Network Coverage location stream
3. **User notified when ready** via local notification
4. **Next test starts only when app is foregrounded**

### Architecture

```
Loop Mode Flow (with background waiting):

┌─────────────────────────────────────────────────────────────┐
│  Foreground: Speed Test Running                             │
│  - RMBTTestRunner active                                    │
│  - CocoaAsyncSocket workers running                         │
│  - NO background activity session                           │
└─────────────────────────────────────────────────────────────┘
                           │
                           │ Test completes
                           ▼
┌─────────────────────────────────────────────────────────────┐
│  Waiting State (can background)                             │
│  - START: BackgroundActivityActor.shared.startActivity()    │
│  - Time tracking: Store waitingStartedAt, compute on resume │
│  - Distance tracking: Subscribe to Coverage location stream │
│  - Ready detection: Post notification, wait for foreground  │
│  - STOP: BackgroundActivityActor.shared.stopActivity()      │
└─────────────────────────────────────────────────────────────┘
                           │
                           │ Time/distance reached + app foregrounded
                           ▼
┌─────────────────────────────────────────────────────────────┐
│  Foreground: Next Speed Test Starting                       │
│  (cycle repeats)                                            │
└─────────────────────────────────────────────────────────────┘
```

### Implementation Plan

#### 1. Create Loop Waiting Coordinator

**New file:** `Sources/Test/LoopMode/LoopWaitingCoordinator.swift`

**Responsibilities:**
- Start/stop `BackgroundActivityActor` during waiting lifecycle
- Subscribe to `RealLocationUpdatesService().locations()` (reuse Network Coverage stream)
- Compute time-based readiness without active timers
- Post local notification when conditions met

**Key methods:**
```swift
@MainActor
class LoopWaitingCoordinator {
    func startWaiting(minutes: UInt, meters: UInt, startLocation: CLLocation?) async
    func stopWaiting() async
    func checkTimeReached() -> Bool  // Compute elapsed, no timer
    func checkDistanceReached(currentLocation: CLLocation) -> Bool
    private func notifyReady(reason: String)  // Local notification
}
```

#### 2. Integrate in RMBTTestViewController

**Modified methods:**

- `goToWaitingState()` (line 622):
  - Create `LoopWaitingCoordinator` instance
  - Call `await coordinator.startWaiting(...)`
  - Remove call to `startWaitingNextTest()` (timer-based approach)

- `cleanup()` (line 545):
  - Call `await coordinator.stopWaiting()`
  - Stop background activity session

- `didBecomeActive(_:)` (line 416):
  - Check if waiting completed in background
  - If ready, call `startTest()` to begin next test

**Deleted methods:**
- `startWaitingNextTest()` (line 588) – replaced by coordinator
- `tick()` (line 569) – no longer needed (time computed on demand)

#### 3. Request Notification Permission

**File:** `Sources/RMBTAppDelegate.swift`

Add to `applicationDidFinishLaunching`:
```swift
UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
    Log.logger.info("Loop Mode notification permission: \(granted)")
}
```

#### 4. NO Changes to RMBTTestRunner

**Keep existing background cancellation:**
- Tests cancelled when backgrounded (line 568-573)
- Loop session survives via existing `onTestCancelled` logic (line 802-807)
- TestViewController transitions to waiting automatically

---

## Benefits of This Approach

### ✅ Compliance & Reliability

| Aspect | Status |
|--------|--------|
| **App Store guidelines** | ✅ Only location tracking in background (legitimate use) |
| **iOS socket constraints** | ✅ No sockets active in background (tests foreground-only) |
| **Test result integrity** | ✅ All measurements in foreground (full system resources) |
| **Background execution budget** | ✅ Minimal (location updates only, proven by Coverage) |

### ✅ User Experience

- **Passive waiting:** User can background app between tests
- **Notification:** Clear prompt to return when next test is ready
- **Transparency:** User understands tests run in foreground, waiting can background
- **Battery efficiency:** No sustained network I/O in background

### ✅ Code Reuse

- **BackgroundActivityActor:** Already implemented for Network Coverage
- **Location stream:** Reuse `RealLocationUpdatesService().locations()`
- **Persistence patterns:** Optional future enhancement (not required for MVP)

---

## Limitations & Trade-offs

### What This Does NOT Solve

1. **App termination:** If iOS kills app during waiting, loop session is lost
   - **Mitigation:** Future enhancement with SwiftData persistence (like Coverage)

2. **Test execution:** Tests still require foreground
   - **Mitigation:** Clear user notification; acceptable UX for measurement app

3. **Instant start:** User must manually open app when notified
   - **Mitigation:** Standard iOS behavior; users are accustomed to this

### Alternative: Make Tests Background-Compatible?

**Not feasible because:**
- Would require rewriting entire test engine (RMBTTestRunner + workers)
- Still subject to iOS socket throttling (unreliable results)
- App Review would likely reject (abuse of background location)
- Network Coverage approach (UDP pings) not applicable to TCP throughput tests

---

## Files to Modify (Minimal Implementation)

| File | Changes | Lines |
|------|---------|-------|
| **New:** `Sources/Test/LoopMode/LoopWaitingCoordinator.swift` | Create waiting coordinator | ~100 |
| `Sources/Test/RMBTTestViewController.swift` | Integrate coordinator, remove timer logic | ~50 |
| `Sources/RMBTAppDelegate.swift` | Request notification permission | ~5 |
| **No change:** `Sources/RMBTTestRunner.swift` | Keep existing background cancellation | 0 |

**Total:** 1 new file, 2 modified files, ~155 lines of code

---

## Testing Checklist

### Basic Flow
- [ ] Start loop with 3 tests, 2-minute wait, 100-meter distance
- [ ] Background app during test #1 → verify test cancelled, transitions to waiting
- [ ] Leave backgrounded for 2 minutes → verify notification posted
- [ ] Foreground app → verify test #2 starts automatically

### Edge Cases
- [ ] Background during waiting → foreground before time/distance reached → verify still waiting
- [ ] Achieve distance threshold while backgrounded → verify notification
- [ ] Revoke location permission during waiting → verify graceful error
- [ ] Toggle airplane mode during waiting → verify loop handles mixed connectivity
- [ ] Force-quit app during waiting → verify no crash on relaunch (session lost, expected)

### Background Execution
- [ ] Monitor `BackgroundActivityActor.isActive()` during waiting (should be true)
- [ ] Verify location updates continue via Coverage stream
- [ ] Verify no socket connections active during waiting
- [ ] Check battery usage (should be comparable to Coverage feature)

---

## Future Enhancements (Out of Scope for Minimal Implementation)

### Persistence for Crash Recovery
Add SwiftData models similar to `PersistentCoverageSession`:
- Store `PersistentLoopSession` (loop UUID, current test count, waiting state)
- On app relaunch, check for incomplete session
- Prompt user: "Resume previous loop test?"

### Progress UI While Backgrounded
- Notification extensions showing "Test 3/10 completed, waiting..."
- Today widget with loop progress bar

### Adaptive Notification Timing
- If user repeatedly ignores notifications, delay or suppress
- If user always responds immediately, be more proactive

---

## References

- **Network Coverage implementation:** Sources/NetworkCoverage/BackgroundActivityActor.swift
- **Current loop waiting logic:** Sources/Test/RMBTTestViewController.swift:569-620
- **Test cancellation:** Sources/RMBTTestRunner.swift:568-573
- **Location stream:** Sources/NetworkCoverage/LocationUpdates/LocationUpdatesService.swift
- **Apple docs:** [Background Execution](https://developer.apple.com/documentation/uikit/app_and_environment/scenes/preparing_your_ui_to_run_in_the_background)

---

## Summary

Loop Mode speed tests **cannot** run in background due to iOS socket lifecycle constraints and App Store policy. The minimal viable solution is to keep tests foreground-only while allowing the **waiting period** to progress in background using `CLBackgroundActivitySession` and the proven Network Coverage location stream. This approach is App Review-compliant, technically reliable, and requires minimal code changes (~155 lines across 3 files).
