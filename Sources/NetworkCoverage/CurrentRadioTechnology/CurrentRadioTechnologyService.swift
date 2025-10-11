//
//  CurrentRadioTechnologyService.swift
//  RMBT
//
//  Created by Jiri Urbasek on 01.04.2025.
//  Copyright © 2025 appscape gmbh. All rights reserved.
//

import Foundation
import CoreTelephony

struct CTTelephonyRadioTechnologyService: CurrentRadioTechnologyService {
    func technologyCode() -> String? {
        let netinfo = CTTelephonyNetworkInfo()
        var radioAccessTechnology: String?

        if let dataIndetifier = netinfo.dataServiceIdentifier {
            radioAccessTechnology = netinfo.serviceCurrentRadioAccessTechnology?[dataIndetifier]
        }
        return radioAccessTechnology
    }
}

#if targetEnvironment(simulator)
/// Provides deterministic-looking radio access technology updates when running inside the simulator.
///
/// CoreTelephony does not return the **current radio access technology** on the simulator.
/// This service mimics the behaviour of the production implementation by keeping the same
/// technology for a short cluster of samples and then occasionally switching to a realistic
/// neighbour technology. The goal is to keep adjacent locations consistent while still
/// demonstrating technology transitions on the coverage map.
@MainActor
final class SimulatorRadioTechnologyService: CurrentRadioTechnologyService {
    private var activeTechnology: String
    private var samplesRemainingInSegment: Int
    private var segmentEndDate: Date
    private let dateProvider: () -> Date
    private let samplesPerSegmentRange: ClosedRange<Int>
    private let segmentDurationRange: ClosedRange<TimeInterval>

    /// Technologies we allow the simulator to cycle through. They originate from CoreTelephony.
    private static let supportedTechnologies: [String] = [
        CTRadioAccessTechnologyNR,
        CTRadioAccessTechnologyNRNSA,
        CTRadioAccessTechnologyLTE,
        CTRadioAccessTechnologyHSDPA,
        CTRadioAccessTechnologyHSUPA,
        CTRadioAccessTechnologyWCDMA,
        CTRadioAccessTechnologyEdge,
        CTRadioAccessTechnologyGPRS
    ]

    /// Neighbour technologies that represent more realistic transitions in the field.
    private static let neighbouringTechnologies: [String: [String]] = [
        CTRadioAccessTechnologyNR: [
            CTRadioAccessTechnologyNR,
            CTRadioAccessTechnologyNRNSA,
            CTRadioAccessTechnologyLTE
        ],
        CTRadioAccessTechnologyNRNSA: [
            CTRadioAccessTechnologyNRNSA,
            CTRadioAccessTechnologyNR,
            CTRadioAccessTechnologyLTE
        ],
        CTRadioAccessTechnologyLTE: [
            CTRadioAccessTechnologyLTE,
            CTRadioAccessTechnologyNRNSA,
            CTRadioAccessTechnologyNR,
            CTRadioAccessTechnologyWCDMA
        ],
        CTRadioAccessTechnologyHSDPA: [
            CTRadioAccessTechnologyHSDPA,
            CTRadioAccessTechnologyHSUPA,
            CTRadioAccessTechnologyWCDMA,
            CTRadioAccessTechnologyLTE
        ],
        CTRadioAccessTechnologyHSUPA: [
            CTRadioAccessTechnologyHSUPA,
            CTRadioAccessTechnologyHSDPA,
            CTRadioAccessTechnologyWCDMA,
            CTRadioAccessTechnologyLTE
        ],
        CTRadioAccessTechnologyWCDMA: [
            CTRadioAccessTechnologyWCDMA,
            CTRadioAccessTechnologyHSDPA,
            CTRadioAccessTechnologyHSUPA,
            CTRadioAccessTechnologyLTE,
            CTRadioAccessTechnologyEdge
        ],
        CTRadioAccessTechnologyEdge: [
            CTRadioAccessTechnologyEdge,
            CTRadioAccessTechnologyWCDMA,
            CTRadioAccessTechnologyGPRS
        ],
        CTRadioAccessTechnologyGPRS: [
            CTRadioAccessTechnologyGPRS,
            CTRadioAccessTechnologyEdge
        ]
    ]

    /// Creates a new simulator radio technology service.
    ///
    /// - Parameters:
    ///   - dateProvider: Injected for testability. Defaults to `Date.init`.
    ///   - samplesPerSegmentRange: Number of consecutive samples that should reuse the same technology before a switch becomes possible.
    ///   - segmentDurationRange: Time interval (in seconds) a segment should last before a switch becomes mandatory.
    init(
        dateProvider: @escaping () -> Date = Date.init,
        samplesPerSegmentRange: ClosedRange<Int> = 6...18,
        segmentDurationRange: ClosedRange<TimeInterval> = 30...90
    ) {
        self.dateProvider = dateProvider
        self.samplesPerSegmentRange = samplesPerSegmentRange
        self.segmentDurationRange = segmentDurationRange

        let initialTechnology = Self.supportedTechnologies.randomElement() ?? CTRadioAccessTechnologyLTE
        activeTechnology = initialTechnology
        samplesRemainingInSegment = 0
        segmentEndDate = dateProvider()
    }

    /// Returns the simulated radio access technology for the current moment and location update.
    func technologyCode() -> String? {
        let now = dateProvider()
        samplesRemainingInSegment -= 1

        if samplesRemainingInSegment <= 0 || now >= segmentEndDate {
            beginNewSegment(startingAt: now)
        }

        return activeTechnology
    }

    private func beginNewSegment(startingAt now: Date) {
        let candidates = Self.neighbouringTechnologies[activeTechnology] ?? Self.supportedTechnologies
        let nextTechnology = candidates.randomElement() ?? activeTechnology

        // Occasionally keep the same technology to create larger contiguous areas.
        if nextTechnology != activeTechnology || Bool.random() {
            activeTechnology = nextTechnology
        }

        samplesRemainingInSegment = Int.random(in: samplesPerSegmentRange)
        segmentEndDate = now.addingTimeInterval(TimeInterval.random(in: segmentDurationRange))

        if samplesRemainingInSegment <= 0 {
            samplesRemainingInSegment = samplesPerSegmentRange.lowerBound
        }
    }
}
#endif
