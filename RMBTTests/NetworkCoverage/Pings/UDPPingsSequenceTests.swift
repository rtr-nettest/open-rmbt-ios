//
//  UDPPingsSequenceTests.swift
//  RMBTTest
//
//  Created by Jiri Urbasek on 18.02.2025.
//  Copyright © 2025 appscape gmbh. All rights reserved.
//

import Testing
import Foundation
@testable import RMBT
import Network

//struct UDPPingsSequenceTests {
//
//    @Test func test() async throws {
//        let sut = makeSUT()
//        let connectionSpy = UDPConnectionSpy()
//        var capturedElements: [PingResult] = []
//
//        for await element in sut {
//            capturedElements.append(element)
//        }
//        #expect(capturedElements.count > 0)
//        #expect(connectionSpy.capturedMessages)
//    }
//
//}
//
//extension UDPPingsSequenceTests {
//    func makeSUT(sessionInitiationResults: [SessionInitiatorStub.SessionInitiationResult]) -> (PingsSequence, SessionInitiatorStub)  {
//        let sessionInitiator = SessionInitiatorStub(initiationResults: sessionInitiationResults)
//        let sut = PingsSequence(
//            pingSender: UDPPingSession(
//                sessionInitiator: sessionInitiator,
//                createUDPClient: {
//                    UDPClient(host: .init($0.serverAddress), port: NWEndpoint.Port(rawValue: $0.serverPort) ?? 444)
//                },
//                timeoutIntervalMs: 1000,
//                now: RMBTHelpers.RMBTCurrentNanos
//            ),
//            clock: clock,
//            frequency: .milliseconds(500)
//        )
//        return (sut, sessionInitiator)
//    }
//
//    final class UDPConnectionSpy: UDPConnectable {
//        enum Message: Equatable {
//            case start(host: String, port: String)
//            case cancel
//            case send(data: Data)
//            case receive
//        }
//
//        var capturedMessages: [Message] = []
//
//        func start(host: String, port: String) async throws(RMBT.UDPConnectionError) {
//            capturedMessages.append(.start(host: host, port: port))
//        }
//        
//        func cancel() {
//            capturedMessages.append(.cancel)
//        }
//        
//        func send(data: Data) async throws {
//            capturedMessages.append(.send(data: data))
//        }
//        
//        func receive() async throws -> Data {
//            capturedMessages.append(.receive)
//            return Data()
//        }
//    }
//
//    final class SessionInitiatorStub: UDPPingSession.SessionInitiating {
//        typealias SessionInitiationResult = Result<UDPPingSession.SessionInitiation, Error>
//
//        private var initiationResults: [SessionInitiationResult] = []
//
//        init(initiationResults: [Result<UDPPingSession.SessionInitiation, Error>]) {
//            self.initiationResults = initiationResults
//        }
//
//        func initiate() async throws -> UDPPingSession.SessionInitiation {
//            try initiationResults.removeFirst().get()
//        }
//    }
//}
//
//
//struct ClockMock: Clock {
//    public struct AnInstant: InstantProtocol, CustomStringConvertible {
//        public typealias Duration = Swift.Duration
//
//        internal let rawValue: Swift.Duration
//
//        internal init(_ rawValue: Swift.Duration) {
//            self.rawValue = rawValue
//        }
//
//        public static func < (lhs: ClockMock.Instant, rhs: ClockMock.Instant) -> Bool {
//            return lhs.rawValue < rhs.rawValue
//        }
//
//        public func advanced(by duration: Swift.Duration) -> ClockMock.Instant {
//            .init(rawValue + duration)
//        }
//
//        public func duration(to other: ClockMock.Instant) -> Duration {
//            other.rawValue - rawValue
//        }
//
//        public var description: String {
//            return "tick \(rawValue)"
//        }
//    }
//
//    typealias Duration = Swift.Duration
//
//    typealias Instant = AnInstant
//
//    var now: AnInstant
//
//    var minimumResolution: Duration
//
//    func sleep(until deadline: AnInstant, tolerance: Duration?) async throws {
//
//    }
//}
