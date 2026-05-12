# Offline Start and Anchored Offsets

As a user, I can start a coverage measurement without internet connectivity. The app collects coverage fences locally. When connectivity is restored — either mid‑measurement or after the user has stopped the test and re‑opens the app later — the session is anchored at the moment the first successful `/coverageRequest` returns. Fences collected before the anchor use negative `offset_ms`; fences after the anchor use positive `offset_ms`. Submission happens per sub‑session.

## Behaviors

### Mid‑measurement recovery (issue #60 scenario B)
- The session initializer suspends retries until reachability reports the device is online again.
- When `/coverageRequest` succeeds, `test_uuid` and `anchor_at` are atomically attached to the live persisted session; in‑memory nil‑UUID fences are retro‑tagged.
- Fences collected before the anchor encode as negative `offset_ms`; later fences as positive.

### Late anchoring after a fully‑offline run (issue #60 scenario A)
- When `stop()` is called on a measurement that never received a `test_uuid`, the persisted session is finalised but kept on disk (it is NOT discarded).
- On the next resend cycle (cold launch, foreground, before a new test, or after a successful submission), the resender:
  1. Detects every finalised session with fences and no `test_uuid` (`finalizedSessionsNeedingAnchor`).
  2. Performs a fresh `/coverageRequest` per stranded session (each session is anchored independently).
  3. Writes the resulting `(test_uuid, anchor_at = now())` back onto the session.
  4. Submits with all offsets negative (since fences were entirely collected before the anchor).
- If `/coverageRequest` still fails (device still offline), the session is left untouched and the next resend cycle tries again.
- Sessions older than the configured `maxResendAge` (default 7 days) are dropped by the existing age‑based cleanup.

## Acceptance
- Fences are persisted even when `test_uuid` is unknown.
- On in‑measurement session initialization, `test_uuid` and `anchor_at` are stored atomically.
- `/coverageResult` requests use the session’s `anchor_at` as `coverageStartDate`.
- Negative offsets are allowed and encoded using signed integers.
- A finalised session without `test_uuid` survives `stop()` and cold‑launch cleanup as long as it has fences AND is younger than `maxResendAge`.
- The next successful resend pass anchors and submits each stranded session independently.

## References
- Sources/NetworkCoverage/Persistence/PersistentFence.swift
- Sources/NetworkCoverage/Persistence/PersistenceServiceActor.swift (`finalizedSessionsNeedingAnchor`, `assignTestUUIDToFinalizedSession`)
- Sources/NetworkCoverage/Persistence/PersistedFencesResender.swift (`anchorStrandedOfflineSessions`)
- Sources/NetworkCoverage/CoverageMeasurementSession/SessionAnchoringService.swift
- Sources/NetworkCoverage/CoverageMeasurementSession/CoverageMeasurementSessionInitializer.swift (`OnlineAwareSessionInitializer`)
- Sources/NetworkCoverage/Reachability/NetworkReachabilityOnlineStatusService.swift
- Sources/NetworkCoverage/SendResult/SendCoverageResultRequest.swift
- RMBTTests/NetworkCoverage/Persistence/ResenderSessionBasedTests.swift
