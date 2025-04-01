//
//  CurrentRadioTechnologyService.swift
//  RMBT
//
//  Created by Jiri Urbasek on 01.04.2025.
//  Copyright © 2025 appscape gmbh. All rights reserved.
//

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
