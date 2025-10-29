# Offline Start and Anchored Offsets

As a user, I can start a coverage measurement without internet connectivity. The app collects coverage fences locally. When connectivity is restored and a session is initialized with the control server, the app anchors the session to that moment. Fences collected before the anchor use negative `offset_ms`; fences after the anchor use positive `offset_ms`. Submission happens per sub‑session.

Acceptance:
- Fences are persisted even when `test_uuid` is unknown.
- On session initialization, `test_uuid` and `anchor_at` are stored atomically.
- `/coverageResult` requests use the session’s `anchor_at` as `coverageStartDate`.
- Negative offsets are allowed and encoded using signed integers.

References:
- Sources/NetworkCoverage/Persistence/PersistentFence.swift
- Sources/NetworkCoverage/Persistence/PersistenceServiceActor.swift
- Sources/NetworkCoverage/Persistence/PersistedFencesResender.swift
- Sources/NetworkCoverage/SendResult/SendCoverageResultRequest.swift
- RMBTTests/NetworkCoverage/Persistence/ResenderSessionBasedTests.swift
