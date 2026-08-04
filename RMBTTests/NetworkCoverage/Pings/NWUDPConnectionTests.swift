//
//  NWUDPConnectionTests.swift
//  RMBTTest
//
//  Copyright © 2025 appscape gmbh. All rights reserved.
//

import Testing
import Network
@testable import RMBT

/// Coverage pings must never be carried by Wi-Fi. On a pinned connection this decides which resolved path may be
/// used for a measurement at all.
@Suite("NWUDPConnection path acceptance")
struct NWUDPConnectionPathAcceptanceTests {
    @Test func whenPinnedAndPathIsCellularOnly_thenItIsAccepted() {
        #expect(acceptsPath(pinnedToCellular: true, usesCellular: true, usesWiFi: false))
    }

    @Test func whenPinnedAndPathUsesWiFi_thenItIsRejected() {
        #expect(!acceptsPath(pinnedToCellular: true, usesCellular: false, usesWiFi: true))
    }

    @Test func whenPinnedAndPathUsesBothCellularAndWiFi_thenItIsRejected() {
        // The shape behind issue #70: Wi-Fi is associated but not the primary path, so nothing pauses the
        // measurement while the socket may still be carried over Wi-Fi.
        #expect(!acceptsPath(pinnedToCellular: true, usesCellular: true, usesWiFi: true))
    }

    @Test func whenPinnedAndPathIsNeitherCellularNorWiFi_thenItIsRejected() {
        #expect(!acceptsPath(pinnedToCellular: true, usesCellular: false, usesWiFi: false))
    }

    @Test func whenNotPinned_thenAnyPathIsAccepted() {
        let acceptedEveryPath = [
            acceptsPath(pinnedToCellular: false, usesCellular: true, usesWiFi: false),
            acceptsPath(pinnedToCellular: false, usesCellular: false, usesWiFi: true),
            acceptsPath(pinnedToCellular: false, usesCellular: false, usesWiFi: false)
        ]

        #expect(acceptedEveryPath == [true, true, true])
    }
}

// MARK: - Factories

private func acceptsPath(pinnedToCellular: Bool, usesCellular: Bool, usesWiFi: Bool) -> Bool {
    NWUDPConnection.isPathAcceptable(
        usesCellular: usesCellular,
        usesWiFi: usesWiFi,
        requiresCellularInterface: pinnedToCellular
    )
}
