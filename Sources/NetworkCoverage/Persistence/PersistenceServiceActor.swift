import Foundation
import SwiftData

enum PersistenceError: Error {
    case noActiveSession
}

@ModelActor
actor PersistenceServiceActor: FencePersistenceService {
    func save(_ fence: Fence) throws {
        guard let session = try latestUnfinishedSession() ?? mostRecentSession() else {
            Log.logger.error("Cannot save fence: no active session")
            throw PersistenceError.noActiveSession
        }

        let persistedFence = PersistentFence(from: fence)
        session.fences.append(persistedFence)

        modelContext.insert(persistedFence)
        try modelContext.save()
        Log.logger.info("Saved fence to session (testUUID: \(session.testUUID ?? "nil"), total fences: \(session.fences.count))")
    }

    func sessionStarted(at date: Date) throws {
        let session = PersistentCoverageSession(
            testUUID: nil,
            loopUUID: nil,
            startedAt: date.microsecondsTimestamp,
            anchorAt: nil,
            finalizedAt: nil
        )
        modelContext.insert(session)
        try modelContext.save()
        Log.logger.info("Session started at \(date)")
    }

    func sessionFinalized(at date: Date) throws {
        guard let session = try latestUnfinishedSession() else {
            Log.logger.info("No unfinished session to finalize")
            return
        }
        if session.startedAt == 0 {
            session.startedAt = date.microsecondsTimestamp
        }
        session.finalizedAt = date.microsecondsTimestamp
        try modelContext.save()
        Log.logger.info("Session finalized (testUUID: \(session.testUUID ?? "nil"), fences: \(session.fences.count))")
    }

    func assignTestUUIDAndAnchor(_ testUUID: String, anchorNow date: Date) throws {
        if let session = try latestUnfinishedSession() {
            Log.logger.info("Assigning UUID to existing session: \(testUUID), fences: \(session.fences.count)")
            session.testUUID = testUUID
            session.anchorAt = date.microsecondsTimestamp
        } else {
            Log.logger.info("Creating new session with UUID: \(testUUID)")
            let session = PersistentCoverageSession(
                testUUID: testUUID,
                loopUUID: nil,
                startedAt: date.microsecondsTimestamp,
                anchorAt: nil,
                finalizedAt: nil
            )
            modelContext.insert(session)
        }
        try modelContext.save()
    }

    // MARK: - Session queries

    /// Warm start: returns only finalized sessions (excludes unfinished sessions without finalizedAt)
    func sessionsToSubmitWarm() throws -> [PersistentCoverageSession] {
        let sessions = try finalizedSessionsSortedByRecency()
        Log.logger.info("sessionsToSubmitWarm found \(sessions.count) session(s)")
        return sessions
    }

    /// Cold start: returns all sessions with testUUID (including unfinished ones)
    func sessionsToSubmitCold() throws -> [PersistentCoverageSession] {
        let descriptor = FetchDescriptor<PersistentCoverageSession>(
            predicate: #Predicate { $0.testUUID != nil },
            sortBy: [SortDescriptor(\.finalizedAt, order: .reverse)]
        )
        let sessions = try modelContext.fetch(descriptor)
        Log.logger.info("sessionsToSubmitCold found \(sessions.count) session(s)")
        for (index, session) in sessions.enumerated() {
            let startedAt = Date(timeIntervalSince1970: Double(session.startedAt) / 1_000_000)
            let anchorAt = session.anchorAt.map { Date(timeIntervalSince1970: Double($0) / 1_000_000) }
            let finalizedAt = session.finalizedAt.map { Date(timeIntervalSince1970: Double($0) / 1_000_000) }
            Log.logger.info("Session[\(index)]: testUUID=\(session.testUUID ?? "nil"), fences=\(session.fences.count), startedAt=\(startedAt), anchorAt=\(anchorAt?.description ?? "nil"), finalizedAt=\(finalizedAt?.description ?? "nil")")
        }
        return sessions
    }

    func delete(_ sessions: [PersistentCoverageSession]) throws {
        Log.logger.info("Deleting \(sessions.count) session(s)")
        for session in sessions {
            Log.logger.info("Deleting session: testUUID=\(session.testUUID ?? "nil"), fences=\(session.fences.count)")
            modelContext.delete(session)
        }
        try modelContext.save()
    }

    func deleteFinalizedNilUUIDSessions() throws {
        let descriptor = FetchDescriptor<PersistentCoverageSession>(
            predicate: #Predicate { $0.testUUID == nil && $0.finalizedAt != nil }
        )
        let sessions = try modelContext.fetch(descriptor)
        guard !sessions.isEmpty else { return }
        sessions.forEach { modelContext.delete($0) }
        try modelContext.save()
    }

    // MARK: - Helpers

    // TODO: can we just keep private variable `currentSession` for storing sesion object instead of feching each time with FetchDescriptor?
    private func latestUnfinishedSession() throws -> PersistentCoverageSession? {
        let descriptor = FetchDescriptor<PersistentCoverageSession>(
            predicate: #Predicate { $0.finalizedAt == nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor).first
    }

    // TODO: use same private variable `currentSession`
    private func mostRecentSession() throws -> PersistentCoverageSession? {
        let descriptor = FetchDescriptor<PersistentCoverageSession>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor).first
    }

    private func finalizedSessionsSortedByRecency() throws -> [PersistentCoverageSession] {
        let descriptor = FetchDescriptor<PersistentCoverageSession>(
            predicate: #Predicate { $0.testUUID != nil && $0.finalizedAt != nil },
            sortBy: [SortDescriptor(\.finalizedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    func cleanupOldSessionsAndOrphans(maxAge: TimeInterval, now: Date, isLaunched: Bool) throws {
        let cutoff = UInt64(max(0, now.timeIntervalSince1970 - maxAge) * 1_000_000)
        let sessions = try modelContext.fetch(FetchDescriptor<PersistentCoverageSession>())

        Log.logger.info("Cleanup: Found \(sessions.count) total session(s), cutoff age: \(maxAge)s")

        var didDelete = false
        var deletedCount = 0
        sessions.forEach { session in
            let startedAt = Date(timeIntervalSince1970: Double(session.startedAt) / 1_000_000)
            let finalizedAt = session.finalizedAt.map { Date(timeIntervalSince1970: Double($0) / 1_000_000) }

            // Drop sessions older than maxAge regardless of UUID presence.
            // Reference time prefers finalizedAt, otherwise startedAt.
            let reference = session.finalizedAt ?? session.startedAt
            if reference < cutoff {
                let referenceDate = Date(timeIntervalSince1970: Double(reference) / 1_000_000)
                Log.logger.info("Cleanup: Deleting old session - testUUID=\(session.testUUID ?? "nil"), fences=\(session.fences.count), referenceDate=\(referenceDate)")
                modelContext.delete(session)
                didDelete = true
                deletedCount += 1
            }

            // If app launched, remove also empty sessions or those which never had a UUID assigned = cannot be sent
            if isLaunched && (session.fences.isEmpty || session.testUUID == nil) {
                Log.logger.info("Cleanup: Deleting orphaned session - testUUID=\(session.testUUID ?? "nil"), fences=\(session.fences.count), startedAt=\(startedAt), finalizedAt=\(finalizedAt?.description ?? "nil")")
                modelContext.delete(session)
                didDelete = true
                deletedCount += 1
                return
            }
        }

        if didDelete {
            try modelContext.save()
            Log.logger.info("Cleaned up \(deletedCount) old/orphaned session(s)")
        } else {
            Log.logger.info("Cleanup: No sessions to delete")
        }
    }
}

extension Date {
    var microsecondsTimestamp: UInt64 {
        let microseconds = timeIntervalSince1970 * 1_000_000
        guard microseconds > 0 else { return 0 }
        return UInt64(microseconds)
    }
}
