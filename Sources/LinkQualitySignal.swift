//
//  LinkQualitySignal.swift
//  RMBT
//
//  iOS provides no public API for actual cellular signal strength (RSSI/RSRP): CoreTelephony's
//  signal values are private/undocumented, so the intro screen's "bars" were previously a static,
//  fake image. Apple's supported signal for connection quality is `NWPath.linkQuality` (Network
//  framework, iOS 26+). We map it to a 0–4 level for the mobile signal indicator.
//
//  Level coding (product spec):
//    3 = link quality unavailable / error (pre-iOS 26, or the path is not satisfied). We use 3 (the
//        previous static default) for backwards compatibility, so a good 5G link renders the same
//        3/4 whether on the old app, the new app, or an older iOS without the linkQuality API.
//    1 = unknown
//    2 = minimal
//    3 = moderate
//    4 = good
//

import Foundation
import UIKit
import Network

enum LinkQualityLevel {
    /// Level used when link quality can't be determined (API unavailable / path not satisfied /
    /// unrecognized future value). Matches the previous static "3 bars" default for compatibility.
    static let unavailableLevel = 3

    /// Maps a network path's link quality to the 1–4 signal level (mobile icon, 4 bars), falling
    /// back to `unavailableLevel`.
    static func level(for path: NWPath) -> Int {
        guard path.status == .satisfied else { return unavailableLevel }
        if #available(iOS 26.0, *) {
            switch path.linkQuality {
            case .unknown: return 1
            case .minimal: return 2
            case .moderate: return 3
            case .good: return 4
            @unknown default: return unavailableLevel
            }
        }
        return unavailableLevel
    }

    /// Fallback for the 3-bar Wi-Fi icon when link quality can't be determined (previous static
    /// "3 bars all active" default).
    static let wifiUnavailableLevel = 3

    /// Maps a network path's link quality to the 1–3 Wi-Fi level (Wi-Fi icon, 3 bars): good → 3,
    /// moderate → 2, minimal → 1, unknown → 1, unavailable/error → 3.
    static func wifiLevel(for path: NWPath) -> Int {
        guard path.status == .satisfied else { return wifiUnavailableLevel }
        if #available(iOS 26.0, *) {
            switch path.linkQuality {
            case .unknown: return 1
            case .minimal: return 1
            case .moderate: return 2
            case .good: return 3
            @unknown default: return wifiUnavailableLevel
            }
        }
        return wifiUnavailableLevel
    }

    /// Human-readable description of a path's link quality, for diagnostic logging.
    static func describe(_ path: NWPath) -> String {
        if #available(iOS 26.0, *) {
            let q: String
            switch path.linkQuality {
            case .unknown: q = "unknown"
            case .minimal: q = "minimal"
            case .moderate: q = "moderate"
            case .good: q = "good"
            @unknown default: q = "future(\(path.linkQuality))"
            }
            return "status=\(path.status) linkQuality=\(q)"
        }
        return "status=\(path.status) linkQuality=unavailable(<iOS26)"
    }
}

/// Monitors the link quality of a specific interface type and reports a 0–4 level.
final class LinkQualityMonitor {
    private let monitor: NWPathMonitor
    private let queue: DispatchQueue
    private let label: String
    private let levelMapper: (NWPath) -> Int

    /// Called on the main thread with the current level whenever the path updates.
    var onLevel: ((Int) -> Void)?

    init(interfaceType: NWInterface.InterfaceType, label: String, levelMapper: @escaping (NWPath) -> Int = LinkQualityLevel.level) {
        self.monitor = NWPathMonitor(requiredInterfaceType: interfaceType)
        self.queue = DispatchQueue(label: "at.rmbt.linkquality.\(label)")
        self.label = label
        self.levelMapper = levelMapper
    }

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let level = self.levelMapper(path)
            Log.logger.debug("LinkQuality[\(self.label)] \(LinkQualityLevel.describe(path)) → level=\(level)")
            DispatchQueue.main.async { self.onLevel?(level) }
        }
        monitor.start(queue: queue)
    }

    func stop() {
        monitor.cancel()
    }
}

/// Renders a signal-bars icon with `barCount` bars. The first `level` bars use `filled`, the rest
/// use `empty`.
enum SignalBarsIcon {
    static func image(level: Int, barCount: Int = 4, filled: UIColor, empty: UIColor, size: CGSize = CGSize(width: 32, height: 26)) -> UIImage {
        let clampedLevel = max(0, min(level, barCount))
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            let spacing = size.width * 0.10
            let barWidth = (size.width - spacing * CGFloat(barCount - 1)) / CGFloat(barCount)
            let corner = barWidth * 0.25
            for index in 0..<barCount {
                let heightFraction = CGFloat(index + 1) / CGFloat(barCount)
                let barHeight = (size.height - 2) * heightFraction + 2
                let x = CGFloat(index) * (barWidth + spacing)
                let y = size.height - barHeight
                let rect = CGRect(x: x, y: y, width: barWidth, height: barHeight)
                (index < clampedLevel ? filled : empty).setFill()
                UIBezierPath(roundedRect: rect, cornerRadius: corner).fill()
            }
        }
    }
}
