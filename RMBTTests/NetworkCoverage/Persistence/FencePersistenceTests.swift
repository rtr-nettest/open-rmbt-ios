//
//  FencePersistenceTests.swift
//  RMBTTest
//
//  Created by Jiri Urbasek on 30.05.2025.
//  Copyright 2025 appscape gmbh. All rights reserved.
//

import Testing
@testable import RMBT
import SwiftData
import CoreLocation

@MainActor
struct FencePersistenceTests {
    @Suite("Given Has No Previously Persisted Data")
    struct GivenHasNoPreviouslyPersitedData {
        @Test func whenPersistedFences_thenTheyArePresentInPersistenceLayer() async throws {
            let sessionID = "session-1"
            let (sut, persistence, _) = makeSUT(testUUID: "dummy")

            try await inSession(sessionID: sessionID, with: sut) {
                try await sut.persist(fence: makeFence(lat: 1, lon: 2, date: Date(timeIntervalSinceReferenceDate: 1), technology: "LTE"))
                try await sut.persist(fence: makeFence(lat: 3, lon: 4, date: Date(timeIntervalSinceReferenceDate: 2), technology: "3G"))
            }

            let persistedFences = try persistence.allPersistedFences()
            try #require(persistedFences.count == 2)

            #expect(persistedFences[0].latitude == 1)
            #expect(persistedFences[0].longitude == 2)
            #expect(persistedFences[0].timestamp == Date(timeIntervalSinceReferenceDate: 1).microsecondsTimestamp)
            #expect(persistedFences[0].technology == "LTE")

            #expect(persistedFences[1].latitude == 3)
            #expect(persistedFences[1].longitude == 4)
            #expect(persistedFences[1].timestamp == Date(timeIntervalSinceReferenceDate: 2).microsecondsTimestamp)
            #expect(persistedFences[1].technology == "3G")

            let persistedSessions = try persistence.persistedSession(forSessionID: sessionID)
            #expect(persistedSessions.count == 1)
            #expect(persistedSessions.first?.testUUID == sessionID)
        }

        @Test func whenSendingFencesSucceds_thenTheyAreRemovedFromPersistenceLayer() async throws {
            let sessionID = "session-1"
            let (sut, persistence, sendService) = makeSUT(testUUID: sessionID, sendResults: [.success(())])
            let fences = [
                makeFence(lat: 1, lon: 2, technology: "LTE", sessionUUID: sessionID),
                makeFence(lat: 3, lon: 4, technology: "3G", sessionUUID: sessionID)
            ]

            try await sut.persistAndSend(fences: fences, sessionID: sessionID)

            #expect(try persistence.allPersistedFences().count == 0)
            #expect(try persistence.allPersistedSessions().count == 0)
            #expect(sendService.capturedSendCalls.count == 1)
        }

        @Test func whenSendingFenceFails_thenTheyAreKeptInPersistenceLayer() async throws {
            let sessionID = "session-1"
            let (sut, persistence, sendService) = makeSUT(testUUID: sessionID, sendResults: [.failure(TestError.sendFailed)])
            let fences = [
                makeFence(lat: 1, lon: 2, date: Date(timeIntervalSinceReferenceDate: 1), technology: "LTE", sessionUUID: sessionID),
                makeFence(lat: 3, lon: 4, date: Date(timeIntervalSinceReferenceDate: 2), technology: "3G", sessionUUID: sessionID)
            ]

            await #expect(throws: TestError.sendFailed) {
                try await sut.persistAndSend(fences: fences, sessionID: sessionID)
            }

            let persistedFences = try persistence.persistedFences(forSessionID: sessionID)
            #expect(sendService.capturedSendCalls.count == 1)
            #expect(persistedFences.count == 2)

            let persistedSessions = try persistence.persistedSession(forSessionID: sessionID)
            #expect(persistedSessions.count == 1)
        }
    }

    @Suite("Given Has Previously Persisted Data")
    struct GivenHasPreviouslyPersitedData {
        @Test func whenSendingFencesSucceeds_thenAttemptsToSendAndRemovesAlsoPreviouslyPersistedFences() async throws {
            let testUUID = "test-uuid"
            let prevTestUUID = "prev-test-uuid"
            let prevSession = PersistentCoverageSession(testUUID: prevTestUUID, startedAt: 10, anchorAt: 10, finalizedAt: 20)
            let prevPersistedFences = [
                makePersistentFence(timestamp: 10),
                makePersistentFence(timestamp: 11)
            ]
            let (sut, persistence, sendService) = makeSUT(
                testUUID: testUUID,
                sendResults: [.success(()), .success(())],
                previouslyPersistedSessions: [(prevSession, prevPersistedFences)]
            )
            let newFences = [makeFence(sessionUUID: testUUID), makeFence(sessionUUID: testUUID), makeFence(sessionUUID: testUUID)]

            try await sut.persistAndSend(fences: newFences, sessionID: testUUID)

            let remainingFences = try persistence.allPersistedFences()
            #expect(remainingFences.count == 0)
            #expect(sendService.capturedSendCalls.count == 2)
            #expect(sendService.capturedSendCalls.map(\.testUUID) == [testUUID, prevTestUUID])
            #expect(sendService.capturedSendCalls.map(\.fences.count) == [newFences.count, prevPersistedFences.count])

            let remainingSessions = try persistence.allPersistedSessions()
            #expect(remainingSessions.count == 0)
        }

        @Test func whenAttemptToSendPreviouslyPersistedFencesFails_thenKeepsThoseFencesPersisted() async throws {
            let testUUID = "test-uuid"
            let prevTestUUID = "prev-test-uuid"
            let prevPrevTestUUID = "prev-prev-test-uuid" // will fail to send

            let prevSession = PersistentCoverageSession(testUUID: prevTestUUID, startedAt: 100, anchorAt: 100, finalizedAt: 120)
            let prevPersistedFences = [
                makePersistentFence(timestamp: 100),
                makePersistentFence(timestamp: 110),
            ]

            let prevPrevSession = PersistentCoverageSession(testUUID: prevPrevTestUUID, startedAt: 10, anchorAt: 10, finalizedAt: 20)
            let prevPrevPersistedFences = [
                makePersistentFence(timestamp: 10),
                makePersistentFence(timestamp: 12),
                makePersistentFence(timestamp: 14),
                makePersistentFence(timestamp: 16)
            ]
            let (sut, persistence, sendService) = makeSUT(
                testUUID: testUUID,
                sendResults: [.success(()), .failure(TestError.sendFailed), .success(())],
                previouslyPersistedSessions: [(prevSession, prevPersistedFences), (prevPrevSession, prevPrevPersistedFences)]
            )
            let newFences = [makeFence(sessionUUID: testUUID), makeFence(sessionUUID: testUUID), makeFence(sessionUUID: testUUID)]

            try await sut.persistAndSend(fences: newFences, sessionID: testUUID)

            // Assert DB state
            #expect(try persistence.persistedFences(forSessionID: prevPrevTestUUID).count == prevPrevPersistedFences.count)
            #expect(try persistence.persistedFences(forSessionID: prevTestUUID).count == 0)

            let remainingSessions = try persistence.allPersistedSessions()
            #expect(remainingSessions.count == 1)
            #expect(remainingSessions.first?.testUUID == prevPrevTestUUID)

            // Assert send spy state
            #expect(sendService.capturedSendCalls.count == 3)
            #expect(sendService.capturedSendCalls.map(\.testUUID) == [testUUID, prevPrevTestUUID, prevTestUUID])
            #expect(sendService.capturedSendCalls.map(\.fences.count) == [newFences.count, prevPrevPersistedFences.count, prevPersistedFences.count])
        }

        @Test func whenSendingPreviouslyPersistedFences_thenMappsThemProperlyToDomainObjects() async throws {
            let persistedTestUUID = "persisted-uuid"
            let newTestUUID = "main-uuid"
            let expectedLat = 50.123456
            let expectedLon = 14.654321
            let expectedPing = 120
            let expectedTimestamp: UInt64 = 1640995200000000 // 2022-01-01 00:00:00 in microseconds
            let expectedTechnology = "5G"

            let persistentSession = PersistentCoverageSession(testUUID: persistedTestUUID, startedAt: expectedTimestamp, anchorAt: expectedTimestamp, finalizedAt: expectedTimestamp + 1000)
            let persistentFence = PersistentFence(
                timestamp: expectedTimestamp,
                latitude: expectedLat,
                longitude: expectedLon,
                avgPingMilliseconds: expectedPing,
                technology: expectedTechnology,
                radiusMeters: 20
            )
            let (sut, _, sendService) = makeSUT(
                testUUID: newTestUUID,
                sendResults: [.success(()), .success(())],
                previouslyPersistedSessions: [(persistentSession, [persistentFence])]
            )

            try await sut.persistAndSend(fences: [makeFence(sessionUUID: newTestUUID)], sessionID: newTestUUID)

            let mappedFence = try #require(sendService.capturedSendCalls.last?.fences.first)

            #expect(mappedFence.startingLocation.coordinate.latitude == expectedLat)
            #expect(mappedFence.startingLocation.coordinate.longitude == expectedLon)
            #expect(mappedFence.dateEntered == expectedTimestamp.dateFromMicroseconds)
            #expect(mappedFence.significantTechnology == expectedTechnology)
            #expect(mappedFence.averagePing == expectedPing)
        }
    }

    @Suite("Given Has Persistent Fences Older Than Max Resend Age")
    struct GivenHasPersistentFencesOlderThenMaxResendAge {
        @Test func whenPersistedFencesAreOlderThanMaxAge_thenTheyAreDeletedWithoutSending() async throws {
            let testUUID = "current-test"
            let oldTestUUID = "old-test"
            let maxAgeSeconds: TimeInterval = 3600 // 1 hour
            let currentTime = Date()

            // Create old fences (older than maxAge)
            let oldTimestamp = currentTime.addingTimeInterval(-maxAgeSeconds - 1).microsecondsTimestamp
            let oldSession = PersistentCoverageSession(testUUID: oldTestUUID, startedAt: oldTimestamp, anchorAt: oldTimestamp, finalizedAt: oldTimestamp + 2000)
            let oldFences = [
                makePersistentFence(testUUID: oldTestUUID, timestamp: oldTimestamp),
                makePersistentFence(testUUID: oldTestUUID, timestamp: oldTimestamp + 1000)
            ]

            // Create recent fences (within maxAge)
            let recentTimestamp = currentTime.addingTimeInterval(-maxAgeSeconds + 600).microsecondsTimestamp
            let recentSession = PersistentCoverageSession(testUUID: "recent-test", startedAt: recentTimestamp, anchorAt: recentTimestamp, finalizedAt: recentTimestamp + 1000)
            let recentFences = [
                makePersistentFence(testUUID: "recent-test", timestamp: recentTimestamp)
            ]

            let (sut, persistence, sendService) = makeSUT(
                testUUID: testUUID,
                sendResults: [.success(()), .success(())],
                previouslyPersistedSessions: [(oldSession, oldFences), (recentSession, recentFences)],
                maxResendAge: maxAgeSeconds
            )

            try await sut.persistAndSend(fences: [makeFence(sessionUUID: testUUID)], sessionID: testUUID)

            #expect(try persistence.allPersistedFences().count == 0)
            #expect(try persistence.allPersistedSessions().count == 0)

            #expect(sendService.capturedSendCalls.count == 2) // newFences + recentFences (old fences not sent)
            #expect(sendService.capturedSendCalls.map(\.testUUID).contains(oldTestUUID) == false)
        }

        @Test func whenPersistedFencesAreWithinMaxAge_thenTheyAreKeptAndSent() async throws {
            let testUUID = "current-test"
            let recentTestUUID = "recent-test"
            let maxAgeSeconds: TimeInterval = 3600 // 1 hour
            let currentTime = Date()

            // Create recent fences (within maxAge)
            let recentTimestamp = currentTime.addingTimeInterval(-maxAgeSeconds + 600).microsecondsTimestamp
            let recentSession = PersistentCoverageSession(testUUID: recentTestUUID, startedAt: recentTimestamp, anchorAt: recentTimestamp, finalizedAt: recentTimestamp + 2000)
            let recentFences = [
                makePersistentFence(timestamp: recentTimestamp),
                makePersistentFence(timestamp: recentTimestamp + 1000)
            ]

            let (sut, persistence, sendService) = makeSUT(
                testUUID: testUUID,
                sendResults: [.success(()), .success(())],
                previouslyPersistedSessions: [(recentSession, recentFences)],
                maxResendAge: maxAgeSeconds
            )

            try await sut.persistAndSend(fences: [makeFence(sessionUUID: testUUID)], sessionID: testUUID)

            #expect(try persistence.allPersistedFences().count == 0) // All should be sent and removed
            #expect(try persistence.allPersistedSessions().count == 0) // All should be sent and removed

            #expect(sendService.capturedSendCalls.count == 2) // newFences + recentFences
            #expect(sendService.capturedSendCalls.map(\.testUUID) == [testUUID, recentTestUUID])
            #expect(sendService.capturedSendCalls.map(\.fences.count) == [1, 2])
        }

        @Test func whenSendingRecentFencesFailsButOldFencesExist_thenOnlyOldFencesAreDeleted() async throws {
            let testUUID = "current-test"
            let recentTestUUID = "recent-test"
            let oldTestUUID = "old-test"
            let maxAgeSeconds: TimeInterval = 3600 // 1 hour
            let currentTime = Date()

            // Create old fences (older than maxAge)
            let oldTimestamp = currentTime.addingTimeInterval(-maxAgeSeconds - 1).microsecondsTimestamp
            let oldSession = PersistentCoverageSession(testUUID: oldTestUUID, startedAt: oldTimestamp, anchorAt: oldTimestamp, finalizedAt: oldTimestamp + 1000)
            let oldFences = [makePersistentFence(timestamp: oldTimestamp)]

            // Create recent fences (within maxAge)
            let recentTimestamp = currentTime.addingTimeInterval(-maxAgeSeconds + 600).microsecondsTimestamp
            let recentSession = PersistentCoverageSession(testUUID: recentTestUUID, startedAt: recentTimestamp, anchorAt: recentTimestamp, finalizedAt: recentTimestamp + 1000)
            let recentFences = [makePersistentFence(timestamp: recentTimestamp)]

            let (sut, persistence, sendService) = makeSUT(
                testUUID: testUUID,
                sendResults: [.success(()), .failure(TestError.sendFailed)], // recent fences fail to send
                previouslyPersistedSessions: [(oldSession, oldFences), (recentSession, recentFences)],
                maxResendAge: maxAgeSeconds
            )

            try await sut.persistAndSend(fences: [makeFence(sessionUUID: testUUID)], sessionID: testUUID)

            let remainingFences = try persistence.allPersistedFences()
            let remainingSessions = try persistence.allPersistedSessions()
            // Only recent fences should remain (old fences deleted, recent fences kept due to send failure)
            #expect(remainingFences.count == 1)
            #expect(remainingSessions.count == 1)
            #expect(remainingSessions.first?.testUUID == recentTestUUID)

            #expect(sendService.capturedSendCalls.count == 2) // current + attempt to send recent
            #expect(sendService.capturedSendCalls.map(\.testUUID).contains(oldTestUUID) == false)
        }
    }

    // MARK: - New Session-Based Persistence Tests

    @Suite("Session-Based Persistence")
    struct SessionBasedPersistence {
        @Test func whenDeletingNilUUIDSession_thenOrphanedFencesAreDeleted() async throws {
            let baseTime = makeBaseTime()
            let (sut, persistence, _) = makeSUT(testUUID: nil)

            try await sut.beginSession(startedAt: baseTime)
            try await sut.persist(fence: makeFence(date: baseTime))
            try await sut.finalizeCurrentSession(at: baseTime.addingTimeInterval(1))
            try await sut.deleteFinalizedNilUUIDSessions()

            let sessions = try persistence.allPersistedSessions()
            #expect(sessions.isEmpty)

            let fences = try persistence.allPersistedFences()
            #expect(fences.isEmpty)
        }

        @Test func whenStoppedWithoutUUID_thenSessionDeleted() async throws {
            let startTime = Date(timeIntervalSinceReferenceDate: 0)
            let (sut, persistence, _) = makeSUT(testUUID: nil)

            try await sut.beginSession(startedAt: startTime)
            try await sut.finalizeCurrentSession(at: startTime.addingTimeInterval(10))
            try await sut.deleteFinalizedNilUUIDSessions()

            let sessions = try persistence.allPersistedSessions()
            #expect(sessions.isEmpty)
        }

        @Test func whenWarmSubmit_thenReturnsOnlyFinalizedSessions() async throws {
            let baseTime = Date(timeIntervalSinceReferenceDate: 100)
            let (sut, persistence, _) = makeSUT(testUUID: nil)

            // Create unfinished session (should NOT be included in warm submit)
            try await sut.beginSession(startedAt: baseTime)
            try await sut.assignTestUUIDAndAnchor("unfinished", anchorNow: baseTime)

            // Create finalized session (should be included in warm submit)
            try await sut.beginSession(startedAt: baseTime.addingTimeInterval(20))
            try await sut.assignTestUUIDAndAnchor("finalized", anchorNow: baseTime.addingTimeInterval(20))
            try await sut.finalizeCurrentSession(at: baseTime.addingTimeInterval(30))

            // Verify database state: both sessions exist
            let allSessions = try persistence.allPersistedSessions()
            #expect(allSessions.count == 2)

            // Verify warm submit behavior: only finalized sessions with testUUID
            let finalizedSessions = allSessions.filter { $0.finalizedAt != nil && $0.testUUID != nil }
            #expect(finalizedSessions.count == 1)
            #expect(finalizedSessions.first?.testUUID == "finalized")
        }

        @Test func whenColdSubmit_thenReturnsAllSessionsWithUUID_includingUnfinished() async throws {
            let baseTime = Date(timeIntervalSinceReferenceDate: 500)
            let (sut, persistence, _) = makeSUT(testUUID: nil)

            // Create older finalized session
            try await sut.beginSession(startedAt: baseTime.addingTimeInterval(-300))
            try await sut.assignTestUUIDAndAnchor("A", anchorNow: baseTime.addingTimeInterval(-300))
            try await sut.finalizeCurrentSession(at: baseTime.addingTimeInterval(-200))

            // Create newer finalized session
            try await sut.beginSession(startedAt: baseTime.addingTimeInterval(-100))
            try await sut.assignTestUUIDAndAnchor("B", anchorNow: baseTime.addingTimeInterval(-100))
            try await sut.finalizeCurrentSession(at: baseTime.addingTimeInterval(-50))

            // Create unfinished session (should be included in cold submit)
            try await sut.beginSession(startedAt: baseTime)
            try await sut.assignTestUUIDAndAnchor("C-unfinished", anchorNow: baseTime)

            // Verify database state: all sessions with testUUID
            let allSessionsWithUUID = try persistence.allPersistedSessions()
                .filter { $0.testUUID != nil }
                .sorted { ($0.finalizedAt ?? 0) > ($1.finalizedAt ?? 0) }

            try #require(allSessionsWithUUID.count == 3)

            // Cold submit should return ALL sessions with UUID, sorted by finalizedAt (nil last)
            // Note: Sessions with nil finalizedAt will sort to the end
            let finalizedSessions = allSessionsWithUUID.filter { $0.finalizedAt != nil }
            #expect(finalizedSessions.count == 2)
            #expect(finalizedSessions.first?.testUUID == "B")
            #expect(finalizedSessions.last?.testUUID == "A")

            let unfinalizedSessions = allSessionsWithUUID.filter { $0.finalizedAt == nil }
            #expect(unfinalizedSessions.count == 1)
            #expect(unfinalizedSessions.first?.testUUID == "C-unfinished")
        }
    }

    @Suite("TestUUID Assignment")
    struct TestUUIDAssignment {
        @Test func whenAssigningTestUUIDToSessionWithNoUUID_thenUUIDIsAssigned() async throws {
            let baseTime = makeDate(offset: 100)
            let testUUID = "test-uuid-123"
            let (sut, persistence, _) = makeSUT(testUUID: nil)

            // Create session without UUID
            try await sut.beginSession(startedAt: baseTime)

            // Assign UUID
            try await sut.assignTestUUIDAndAnchor(testUUID, anchorNow: baseTime)

            // Verify UUID was assigned
            let sessions = try persistence.allPersistedSessions()
            try #require(sessions.count == 1)
            #expect(sessions.first?.testUUID == testUUID)
            #expect(sessions.first?.anchorAt == baseTime.microsecondsTimestamp)
        }

        @Test func whenAssigningSameTestUUIDAgain_thenNoNewSessionIsCreated() async throws {
            let baseTime = makeDate(offset: 100)
            let testUUID = "test-uuid-123"
            let (sut, persistence, _) = makeSUT(testUUID: nil)

            // Create session and assign UUID
            try await sut.beginSession(startedAt: baseTime)
            try await sut.assignTestUUIDAndAnchor(testUUID, anchorNow: baseTime)

            // Assign same UUID again
            try await sut.assignTestUUIDAndAnchor(testUUID, anchorNow: baseTime.addingTimeInterval(10))

            // Verify no duplicate session was created
            let sessions = try persistence.allPersistedSessions()
            #expect(sessions.count == 1)
            #expect(sessions.first?.testUUID == testUUID)
        }

        @Test func whenAssigningDifferentTestUUIDToExistingSession_thenNewSessionIsCreatedAtomically() async throws {
            let baseTime = makeDate(offset: 100)
            let firstUUID = "uuid-A"
            let secondUUID = "uuid-B"
            let (sut, persistence, _) = makeSUT(testUUID: nil)

            // Create session with first UUID
            try await sut.beginSession(startedAt: baseTime)
            try await sut.assignTestUUIDAndAnchor(firstUUID, anchorNow: baseTime)

            // Assign DIFFERENT UUID - should create NEW session atomically
            try await sut.assignTestUUIDAndAnchor(secondUUID, anchorNow: baseTime.addingTimeInterval(60))

            // Verify TWO sessions exist
            let sessions = try persistence.allPersistedSessions()
            #expect(sessions.count == 2, "Expected 2 sessions but got \(sessions.count) - UUID was overwritten instead of creating new session!")

            let expectedFinalizationTimestamp = baseTime.addingTimeInterval(60).microsecondsTimestamp

            // Verify original session unchanged
            let originalSession = sessions.first { $0.testUUID == firstUUID }
            try #require(originalSession != nil, "Original session with UUID '\(firstUUID)' was lost!")
            #expect(originalSession?.testUUID == firstUUID)
            #expect(originalSession?.finalizedAt == expectedFinalizationTimestamp, "Original session must be finalized with timestamp \(expectedFinalizationTimestamp)")

            // Verify new session created
            let newSession = sessions.first { $0.testUUID == secondUUID }
            try #require(newSession != nil, "New session with UUID '\(secondUUID)' was not created!")
            #expect(newSession?.testUUID == secondUUID)
            #expect(newSession?.finalizedAt == nil, "New session should not be finalized immediately")
        }

        @Test func whenAssigningDifferentTestUUIDWithFences_thenNewSessionIsCreatedAndFencesRemainWithOriginal() async throws {
            let baseTime = makeDate(offset: 100)
            let firstUUID = "uuid-with-fences"
            let secondUUID = "uuid-new-empty"
            let (sut, persistence, _) = makeSUT(testUUID: nil)

            // Create session with first UUID and add fences
            try await sut.beginSession(startedAt: baseTime)
            try await sut.assignTestUUIDAndAnchor(firstUUID, anchorNow: baseTime)

            // Add fences to first session
            let fencesInFirstSession = [
                makeFence(lat: 1.0, lon: 1.0, date: baseTime.addingTimeInterval(1)),
                makeFence(lat: 2.0, lon: 2.0, date: baseTime.addingTimeInterval(2)),
                makeFence(lat: 3.0, lon: 3.0, date: baseTime.addingTimeInterval(3)),
                makeFence(lat: 4.0, lon: 4.0, date: baseTime.addingTimeInterval(4)),
                makeFence(lat: 5.0, lon: 5.0, date: baseTime.addingTimeInterval(5))
            ]
            try await sut.persist(fences: fencesInFirstSession)

            // Assign DIFFERENT UUID - should create NEW session WITHOUT stealing fences
            try await sut.assignTestUUIDAndAnchor(secondUUID, anchorNow: baseTime.addingTimeInterval(60))

            // Verify TWO sessions exist
            let sessions = try persistence.allPersistedSessions()
            #expect(sessions.count == 2, "Expected 2 sessions but got \(sessions.count)")

            let expectedFinalizationTimestamp = baseTime.addingTimeInterval(60).microsecondsTimestamp

            // Verify original session STILL has its fences
            let originalSession = sessions.first { $0.testUUID == firstUUID }
            try #require(originalSession != nil, "Original session was lost!")
            #expect(originalSession?.fences.count == 5, "Original session lost its fences! Expected 5, got \(originalSession?.fences.count ?? 0)")
            #expect(originalSession?.finalizedAt == expectedFinalizationTimestamp, "Original session must be finalized with timestamp \(expectedFinalizationTimestamp)")

            // Verify new session has NO fences (starts fresh)
            let newSession = sessions.first { $0.testUUID == secondUUID }
            try #require(newSession != nil, "New session was not created!")
            #expect(newSession?.fences.count == 0, "New session should start with 0 fences, got \(newSession?.fences.count ?? 0)")
            #expect(newSession?.finalizedAt == nil, "New session should not be finalized immediately")

            // Verify total fence count
            let allFences = try persistence.allPersistedFences()
            #expect(allFences.count == 5, "Fences were lost or duplicated! Expected 5, got \(allFences.count)")
        }

        @Test func whenReceivingHourlyTestUUIDUpdates_thenCreatesMultipleSeparateSessions() async throws {
            let baseTime = Date(timeIntervalSinceReferenceDate: 1000)
            let (sut, persistence, _) = makeSUT(testUUID: nil)

            // Simulate real log behavior: hourly UUID reassignments
            // Hour 1: Create session and assign first UUID
            try await sut.beginSession(startedAt: baseTime)
            try await sut.assignTestUUIDAndAnchor("uuid-hour-1", anchorNow: baseTime)

            // Add fences during hour 1
            let fencesHour1 = (0..<222).map { i in
                makeFence(lat: Double(i), lon: Double(i), date: baseTime.addingTimeInterval(Double(i)))
            }
            try await sut.persist(fences: fencesHour1)

            // Hour 2: Assign different UUID (should create NEW session)
            let hour2Time = baseTime.addingTimeInterval(3600)
            try await sut.assignTestUUIDAndAnchor("uuid-hour-2", anchorNow: hour2Time)

            // Add fences during hour 2
            let fencesHour2 = (0..<7).map { i in
                makeFence(lat: 50.0 + Double(i), lon: 50.0 + Double(i), date: hour2Time.addingTimeInterval(Double(i)))
            }
            try await sut.persist(fences: fencesHour2)

            // Hour 3: Assign yet another different UUID (should create ANOTHER new session)
            let hour3Time = baseTime.addingTimeInterval(7200)
            try await sut.assignTestUUIDAndAnchor("uuid-hour-3", anchorNow: hour3Time)

            // Verify THREE separate sessions exist
            let sessions = try persistence.allPersistedSessions()
            #expect(sessions.count == 3, "Expected 3 separate sessions but got \(sessions.count) - UUIDs were overwritten!")

            // Verify each session has correct UUID
            let session1 = sessions.first { $0.testUUID == "uuid-hour-1" }
            let session2 = sessions.first { $0.testUUID == "uuid-hour-2" }
            let session3 = sessions.first { $0.testUUID == "uuid-hour-3" }

            try #require(session1 != nil, "Session 1 was lost!")
            try #require(session2 != nil, "Session 2 was not created!")
            try #require(session3 != nil, "Session 3 was not created!")

            let expectedHour1Finalization = hour2Time.microsecondsTimestamp
            let expectedHour2Finalization = hour3Time.microsecondsTimestamp
            #expect(session1?.finalizedAt == expectedHour1Finalization, "Session 1 must be finalized at \(expectedHour1Finalization)")
            #expect(session2?.finalizedAt == expectedHour2Finalization, "Session 2 must be finalized at \(expectedHour2Finalization)")
            #expect(session3?.finalizedAt == nil, "Latest session should stay unfinished")

            // Verify fence distribution
            #expect(session1?.fences.count == 222, "Session 1 should have 222 fences, got \(session1?.fences.count ?? 0)")
            #expect(session2?.fences.count == 7, "Session 2 should have 7 fences, got \(session2?.fences.count ?? 0)")
            #expect(session3?.fences.count == 0, "Session 3 should have 0 fences, got \(session3?.fences.count ?? 0)")
        }
    }

    @Suite("Fence Persistence Behavior")
    struct FencePersistenceBehavior {
        @Test func whenFenceSaved_thenAlwaysSavedToLatestUnfinishedSession() async throws {
            let session1UUID = "session-1"
            let session2UUID = "session-2"
            let (sut, persistence, _) = makeSUT(testUUID: "dummy")

            // Create session 1
            try await sut.beginSession(startedAt: Date(timeIntervalSinceReferenceDate: 1))
            try await sut.assignTestUUIDAndAnchor(session1UUID, anchorNow: Date(timeIntervalSinceReferenceDate: 1))

            // Create session 2 (finalizes session 1)
            try await sut.assignTestUUIDAndAnchor(session2UUID, anchorNow: Date(timeIntervalSinceReferenceDate: 5))

            // Save fence - should go to session 2 (latest unfinished) regardless of sessionUUID
            var fence = makeFence(lat: 3.0, lon: 4.0, date: Date(timeIntervalSinceReferenceDate: 6))
            fence.sessionUUID = session1UUID  // Even though fence has session1UUID...
            try await sut.persist(fence: fence)

            // Verify fence was saved to session 2 (latest unfinished), not session 1
            let session1Fences = try persistence.persistedFences(forSessionID: session1UUID)
            let session2Fences = try persistence.persistedFences(forSessionID: session2UUID)

            #expect(session1Fences.count == 0, "Fence should NOT be in finalized session 1")
            #expect(session2Fences.count == 1, "Fence should be in latest unfinished session 2")
            #expect(session2Fences.first?.latitude == 3.0)
            #expect(session2Fences.first?.longitude == 4.0)
        }

        @Test func whenMultipleFencesSaved_thenAllGoToLatestUnfinishedSession() async throws {
            let session1UUID = "session-1"
            let session2UUID = "session-2"
            let (sut, persistence, _) = makeSUT(testUUID: "dummy")

            // Create session 1
            try await sut.beginSession(startedAt: Date(timeIntervalSinceReferenceDate: 1))
            try await sut.assignTestUUIDAndAnchor(session1UUID, anchorNow: Date(timeIntervalSinceReferenceDate: 1))

            // Create session 2 (finalizes session 1)
            try await sut.assignTestUUIDAndAnchor(session2UUID, anchorNow: Date(timeIntervalSinceReferenceDate: 5))

            // Save multiple fences with different sessionUUIDs - all should go to session 2
            var fence1 = makeFence(lat: 1.0, lon: 1.0)
            fence1.sessionUUID = session1UUID

            var fence2 = makeFence(lat: 2.0, lon: 2.0)
            fence2.sessionUUID = session1UUID

            var fence3 = makeFence(lat: 3.0, lon: 3.0)
            fence3.sessionUUID = session2UUID

            try await sut.persist(fence: fence1)
            try await sut.persist(fence: fence2)
            try await sut.persist(fence: fence3)

            // Verify all fences saved to session 2 (latest unfinished)
            let session1Fences = try persistence.persistedFences(forSessionID: session1UUID)
            let session2Fences = try persistence.persistedFences(forSessionID: session2UUID)

            #expect(session1Fences.count == 0, "Session 1 should have 0 fences (finalized)")
            #expect(session2Fences.count == 3, "Session 2 should have all 3 fences (latest unfinished)")

            let session2Lats = session2Fences.map(\.latitude).sorted()
            #expect(session2Lats == [1.0, 2.0, 3.0])
        }
    }
}

// MARK: - Test Helpers

private struct SendCall {
    let testUUID: String
    let fences: [Fence]
}

private func makeSUT(
    testUUID: String?,
    sendResults: [Result<Void, Error>] = [.success(())],
    previouslyPersistedSessions: [(PersistentCoverageSession, [PersistentFence])] = [],
    maxResendAge: TimeInterval = Date().timeIntervalSince1970 * 1000,
    dateNow: @escaping () -> Date = Date.init
) -> (sut: SUT, persistence: PersistenceLayerSpy, sendService: SendCoverageResultsServiceFactory) {
    let database = UserDatabase(useInMemoryStore: true)
    let persistence = PersistenceLayerSpy(modelContext: database.modelContext)
    let sendServiceFactory = SendCoverageResultsServiceFactory(sendResults: sendResults)

    // Insert prefilled sessions with their fences into modelContext
    for (session, fences) in previouslyPersistedSessions {
        session.fences = fences
        database.modelContext.insert(session)
    }
    try! database.modelContext.save()

    let services = NetworkCoverageFactory(
        database: database,
        maxResendAge: maxResendAge
    ).services(testUUID: testUUID, startDate: Date(timeIntervalSinceReferenceDate: 0), dateNow: dateNow, sendResultsServiceMaker: { testUUID, _ in
        sendServiceFactory.createService(for: testUUID)
    })
    let sut = SUT(fencePersistenceService: services.0, sendResultsServices: services.1)

    return (sut, persistence, sendServiceFactory)
}

final class SUT {
    private let fencePersistenceService: any FencePersistenceService
    private let sendResultsServices: any SendCoverageResultsService

    init(fencePersistenceService: some FencePersistenceService, sendResultsServices: some SendCoverageResultsService) {
        self.fencePersistenceService = fencePersistenceService
        self.sendResultsServices = sendResultsServices
    }

    func startSession(on date: Date) async throws {
        try await fencePersistenceService.sessionStarted(at: date)
    }

    func recordSessionID(id: String, on date: Date) async throws {
        try await fencePersistenceService.assignTestUUIDAndAnchor(id, anchorNow: date)
    }

    func stopSession(on date: Date) async throws {
        try await fencePersistenceService.sessionFinalized(at: date)
    }

    func persist(fence: Fence) async throws {
        try await fencePersistenceService.save(fence)
    }

    func persist(fences: [Fence]) async throws {
        for fence in fences {
            try await persist(fence: fence)
        }
    }

    func send(fences: [Fence]) async throws {
        try await sendResultsServices.send(fences: fences)
    }

    /// Helper to persist fences within a single session and then send them
    func persistAndSend(fences: [Fence], sessionID: String) async throws {
        try await inSession(sessionID: sessionID, with: self) {
            try await self.persist(fences: fences)
        }
        try await self.send(fences: fences)
    }

    // MARK: - Session-Based Helpers

    /// Begins a new session. Equivalent to calling sessionStarted.
    func beginSession(startedAt date: Date) async throws {
        try await fencePersistenceService.sessionStarted(at: date)
    }

    /// Assigns test UUID and anchor to the current session
    func assignTestUUIDAndAnchor(_ testUUID: String, anchorNow: Date) async throws {
        try await fencePersistenceService.assignTestUUIDAndAnchor(testUUID, anchorNow: anchorNow)
    }

    /// Finalizes the current session
    func finalizeCurrentSession(at date: Date) async throws {
        try await fencePersistenceService.sessionFinalized(at: date)
    }

    /// Deletes finalized sessions that have nil UUID
    func deleteFinalizedNilUUIDSessions() async throws {
        try await fencePersistenceService.deleteFinalizedNilUUIDSessions()
    }
}

private func inSession(
    started: Date = Date(timeIntervalSinceReferenceDate: 1),
    finalized: Date = Date(timeIntervalSinceReferenceDate: 2),
    sessionID: String = UUID().uuidString,
    with sut: SUT,
    action: () async throws -> Void
) async throws {
    try await sut.startSession(on: started)
    try await sut.recordSessionID(id: sessionID, on: started)

    try await action()

    try await sut.stopSession(on: finalized)
}

private final class PersistenceLayerSpy {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func allPersistedFences() throws -> [PersistentFence] {
        try modelContext.fetch(FetchDescriptor<PersistentFence>())
    }

    func persistedFences(forSessionID testUUID: String) throws -> [PersistentFence] {
        let sessions = try persistedSession(forSessionID: testUUID)
        return sessions
            .map(\.fences)
            .flatMap { $0 }
    }

    func allPersistedSessions() throws -> [PersistentCoverageSession] {
        try modelContext.fetch(FetchDescriptor<PersistentCoverageSession>())
    }

    func persistedSession(forSessionID testUUID: String) throws -> [PersistentCoverageSession] {
        let descriptor = FetchDescriptor<PersistentCoverageSession>(
            predicate: #Predicate { $0.testUUID ==  testUUID}
        )
        return try modelContext.fetch(descriptor)
    }
}

private func makeFence(
    lat: CLLocationDegrees = Double.random(in: -90...90),
    lon: CLLocationDegrees = Double.random(in: -180...180),
    date: Date = Date(timeIntervalSinceReferenceDate: TimeInterval.random(in: 0...10000)),
    technology: String? = ["3G", "4G", "5G", "LTE"].randomElement(),
    averagePing: Int? = nil,
    sessionUUID: String? = nil
) -> Fence {
    var fence = Fence(
        startingLocation: CLLocation(latitude: lat, longitude: lon),
        dateEntered: date,
        technology: technology,
        radiusMeters: Double.random(in: 1...100)
    )

    if let ping = averagePing {
        fence.append(ping: PingResult(result: .interval(.milliseconds(ping)), timestamp: date))
    }

    fence.sessionUUID = sessionUUID

    return fence
}

func makePersistentFence(testUUID: String = "TODO: Delete", timestamp: UInt64) -> PersistentFence {
    .init(
        timestamp: timestamp,
        latitude: Double.random(in: -90...90),
        longitude: Double.random(in: -180...180),
        avgPingMilliseconds: Int.random(in: 10...500),
        technology: ["3G", "4G", "5G", "LTE"].randomElement(),
        radiusMeters: 20
    )
}

private func makeBaseTime() -> Date {
    Date()
}

private enum TestError: Error {
    case sendFailed
}

extension Date {
    var microsecondsTimestamp: UInt64 {
        let microseconds = timeIntervalSince1970 * 1_000_000
        guard microseconds > 0 else { return 0 }
        return UInt64(microseconds)
    }
}

extension UInt64 {
    var dateFromMicroseconds: Date {
        Date(timeIntervalSince1970: Double(self) / 1_000_000)
    }
}

private final class SendCoverageResultsServiceFactory {
    private(set) var capturedSendCalls: [SendCall] = []
    private var sendResults: [Result<Void, Error>]

    init(sendResults: [Result<Void, Error>] = [.success(())]) {
        self.sendResults = sendResults
    }

    func createService(for testUUID: String) -> SendCoverageResultsServiceWrapper {
        let service = SendCoverageResultsServiceSpy(sendResult: sendResults.removeFirst())

        return SendCoverageResultsServiceWrapper(
            originalService: service,
            onSend: { [weak self] fences in
                self?.capturedSendCalls.append(SendCall(testUUID: testUUID, fences: fences))
            }
        )
    }
}

final class SendCoverageResultsServiceWrapper: SendCoverageResultsService {
    private let originalService: SendCoverageResultsServiceSpy
    private let onSend: ([Fence]) -> Void

    init(originalService: SendCoverageResultsServiceSpy, onSend: @escaping ([Fence]) -> Void) {
        self.originalService = originalService
        self.onSend = onSend
    }

    func send(fences: [Fence]) async throws {
        onSend(fences)
        try await originalService.send(fences: fences)
    }
}
