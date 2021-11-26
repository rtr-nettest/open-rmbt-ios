//
//  RMBTHistoryResult.swift
//  RMBT
//
//  Created by Polina Gurina on 26.11.2021.
//  Copyright © 2021 appscape gmbh. All rights reserved.
//

import Foundation

extension RMBTHistoryResult {
    var timeStringIn24hFormat: String? {
        get {
            let df = DateFormatter(withFormat: "dd.MM.yy, HH:mm:ss", locale: Locale.current.languageCode ?? "en_US")
            if let date = timestamp {
                return df.string(from: date)
            }
            return nil
        }
    }
}
