//
//  UIImage+ResultClass.swift
//  RMBT
//
//  Created by Jiri Urbasek on 23.01.2025.
//  Copyright © 2025 appscape gmbh. All rights reserved.
//

import UIKit

extension UIImage {
    static func downloadIconByResultClass(_ classification: Int?) -> UIImage? {
        UIImage(named: "down-\(classification ?? 0)") ?? UIImage(named: "down-0")
    }

    static func uploadIconByResultClass(_ classification: Int?) -> UIImage? {
        UIImage(named: "up-\(classification ?? 0)") ?? UIImage(named: "up-0")
    }

    static func pingIconByResultClass(_ classification: Int?) -> UIImage? {
        UIImage(named: "ping-\(classification ?? 0)") ?? UIImage(named: "ping-0")
    }
}
