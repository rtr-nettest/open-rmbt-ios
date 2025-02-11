//
//  NetworkCoverageViewPresenter.swift
//  RMBT
//
//  Created by Jiri Urbasek on 12/18/24.
//  Copyright © 2024 appscape gmbh. All rights reserved.
//

import CoreLocation
import SwiftUI

struct LocationItem: Identifiable, Hashable {
    let id: UUID
    let date: Date
    let coordinate: CLLocationCoordinate2D
    let technology: String
    let averagePing: String
    let isSelected: Bool
    let color: Color
}

struct SelectedLocationItemDetail: Equatable, Identifiable {
    let id: UUID
    let date: String
    let technology: String
    let averagePing: String
    let color: Color
}

@MainActor struct NetworkCoverageViewPresenter {
    let locale: Locale

    let selectedItemDateFormatter: DateFormatter

    struct Fence: Identifiable, Equatable {
        let locationItem: LocationItem
        let locationArea: LocationArea

        var id: LocationArea { locationArea }
    }

    init(locale: Locale) {
        self.locale = locale
        selectedItemDateFormatter = {
            let dateFormatter = DateFormatter()
            dateFormatter.locale = locale
            dateFormatter.dateStyle = .medium
            dateFormatter.timeStyle = .medium
            return dateFormatter
        }()
    }

    func displayValue(forRadioTechnology technology: String) -> String {
        technology.radioTechnologyDisplayValue ?? technology
    }

    func fences(from viewModel: NetworkCoverageViewModel) -> [Fence] {
        viewModel.locationAreas.map {
            .init(locationItem: locationItem(from: $0, selectedArea: viewModel.selectedArea), locationArea: $0)
        }
    }

    func locationItem(from area: LocationArea, selectedArea: LocationArea?) -> LocationItem {
        .init(
            id: area.id,
            date: area.time,
            coordinate: area.startingLocation.coordinate,
            technology: area.significantTechnology?.radioTechnologyDisplayValue ?? "N/A",
            averagePing: area.averagePing.map { "\($0) ms" } ?? "",
            isSelected: selectedArea?.id == area.id,
            color: color(for: area.significantTechnology)
        )
    }

    func selectedItemDetail(from area: LocationArea) -> SelectedLocationItemDetail {
        .init(
            id: area.id,
            date: selectedItemDateFormatter.string(from: area.time),
            technology: area.significantTechnology?.radioTechnologyDisplayValue ?? "N/A",
            averagePing: area.averagePing.map { "\($0) ms" } ?? "",
            color: color(for: area.significantTechnology)
        )
    }

    private func color(for technology: String?) -> Color {
        .init(uiColor: .byResultClass(technology?.radioTechnologyColorClassification))
    }
}

extension CLLocation: @retroactive Identifiable {
    public var id: String { "\(coordinate.latitude),\(coordinate.longitude)" }
}

extension PingResult {
    var displayValue: String {
        switch self {
        case .interval(let duration):
            "\(duration.milliseconds) ms"
        case .error:
            "err"
        }
    }
}

extension LocationArea {
    var significantTechnology: String? {
        technologies.last
    }
}

extension String {
    var radioTechnologyDisplayValue: String? {
        if
            let code = radioTechnologyCode,
            let celularCodeDescription = RMBTNetworkTypeConstants.cellularCodeDescriptionDictionary[code] {
            return celularCodeDescription.radioTechnologyDisplayValue
        } else {
            return nil
        }
    }

    var radioTechnologyColorClassification: Int? {
        if
            let code = radioTechnologyCode,
            let celularCodeDescription = RMBTNetworkTypeConstants.cellularCodeDescriptionDictionary[code] {
            return celularCodeDescription.radioTechnologyColorClassification
        } else {
            return nil
        }
    }
}

extension RMBTNetworkTypeConstants.NetworkType {
    var radioTechnologyDisplayValue: String {
        switch self {
        case .type2G: "2G"
        case .type3G: "3G"
        case .type4G: "4G"
        case .type5G, .type5GNSA, .type5GAvailable: "5G"
        case .wlan, .lan, .bluetooth, .unknown, .browser: "--"
        }
    }

    var radioTechnologyColorClassification: Int? {
        switch self {
        case .type2G: 1
        case .type3G: 2
        case .type4G: 3
        case .type5G, .type5GNSA, .type5GAvailable: 4
        case .wlan, .lan, .bluetooth, .unknown, .browser: nil
        }
    }
}
