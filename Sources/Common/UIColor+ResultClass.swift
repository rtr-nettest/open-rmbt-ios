//
//  UIColor.swift
//  RMBT
//
//  Created by Polina Gurina on 24.11.2021.
//  Copyright © 2021 appscape gmbh. All rights reserved.
//

import UIKit

extension UIColor {
    static func byResultClass(_ classification: Int?) -> UIColor {
        switch(classification) {
        case 1:
            return UIColor(hex: "F5001C")
        case 2:
            return UIColor(hex: "FFBA00")
        case 3:
            return UIColor(hex: "59B200")
        case 4:
            return UIColor(hex: "007C0E")
        default:
            return UIColor(hex: "F2F3F5")
        }
    }

    convenience init(hex: String) {
        var cString:String = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        if (cString.hasPrefix("#")) {
            cString.remove(at: cString.startIndex)
        }

        if ((cString.count) != 6) {
            self.init()
        }

        var rgbValue:UInt64 = 0
        Scanner(string: cString).scanHexInt64(&rgbValue)

        self.init(
            red: CGFloat((rgbValue & 0xFF0000) >> 16) / 255.0,
            green: CGFloat((rgbValue & 0x00FF00) >> 8) / 255.0,
            blue: CGFloat(rgbValue & 0x0000FF) / 255.0,
            alpha: CGFloat(1.0)
        )
    }
}
