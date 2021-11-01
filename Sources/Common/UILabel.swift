//
//  UILabel.swift
//  RMBT
//
//  Created by Polina on 29.10.2021.
//  Copyright © 2021 appscape gmbh. All rights reserved.
//

import UIKit

extension UILabel {
    @IBInspectable var localizableText: String? {
        get { return text }
        set { text = NSLocalizedString(newValue!, comment: "") }
    }
}
