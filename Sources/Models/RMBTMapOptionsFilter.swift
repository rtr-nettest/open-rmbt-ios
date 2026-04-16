//
//  RMBTMapOptionsFilter.swift
//  RMBT
//
//  Created by Sergey Glushchenko on 18.12.2021.
//  Copyright © 2021 appscape gmbh. All rights reserved.
//

import UIKit

@objc final class RMBTMapOptionsFilter: NSObject {
    @objc public var icon: UIImage? {
        switch iconValue {
        case "MAP_FILTER_PERIOD":
            return UIImage(named: "map_options_period")
        case "MAP_FILTER_CARRIER":
            return UIImage(named: "map_options_provider")
        case "MAP_FILTER_STATISTICS":
            return UIImage(named: "map_options_statistic")
        case "MAP_FILTER_TECHNOLOGY":
            return UIImage(named: "map_options_technologies")
        case "MAP_TYPE":
            return UIImage(named: "map_options_layout")
        default: break
        }
        // TODO: Remake it, because if we will use another language then we should put localization for each word from response
        switch title {
        case "Zeitraum", "Period":
            return UIImage(named: "map_options_period")
        case "Betreiber", "Operator":
            return UIImage(named: "map_options_provider")
        case "Statistik", "Statistics":
            return UIImage(named: "map_options_statistic")
        case "Technologie", "Technology":
            return UIImage(named: "map_options_technologies")
        default:
            return nil
        }
    }
    
    var activeValueTitle: String? {
        if let activeOption = activeValue?.activeOption {
            var values: [String] = []
            if let title = activeValue?.title {
                values.append(title)
            }
            if activeOption.title.count > 0 {
                values.append(activeOption.title)
            }
            
            return values.joined(separator: "/")
        }
        return activeValue?.title
    }
    
    @objc public var title: String = ""
    @objc public var iconValue: String = ""
    @objc public var isDefault = false
    @objc public var dependsOnMapTypeIsMobile = false
    @objc public var possibleValues: [RMBTMapOptionsFilterValue] = []
    @objc public var activeValue: RMBTMapOptionsFilterValue?
    
    @objc(initWithResponse:) public init(with response: [String: Any]) {
        super.init()
        title = response["title"] as? String ?? ""
        iconValue = response["icon"] as? String ?? ""
        isDefault = response["default"] as? Bool ?? false
        if let dependsOn = response["depends_on"] as? [String:Any], let mapTypeIsMobile = dependsOn["map_type_is_mobile"] as? Bool {
            dependsOnMapTypeIsMobile = mapTypeIsMobile
        }
        let options = response["options"] as? [[String: Any]] ?? []
        possibleValues = options.map { RMBTMapOptionsFilterValue(with: $0) }

        // Prefer explicit top-level default; fall back to first value with a default sub-option
        activeValue =
            possibleValues.first(where: \.isDefault) ??
            possibleValues.first(where: { $0.activeOption != nil })

        Log.logger.debug("\(title) (\(iconValue), dependsMobile=\(dependsOnMapTypeIsMobile)): activeValue='\(activeValue?.title ?? "nil")' (isDefault=\(activeValue?.isDefault ?? false)) with \(possibleValues.count) options: [\(possibleValues.map { $0.title }.joined(separator: ", "))]")
    }
}
