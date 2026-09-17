//
//  Color+Ext.swift
//  RMBT
//
//  Created by Jiri Urbasek on 26.06.2025.
//  Copyright © 2025 appscape gmbh. All rights reserved.
//

import SwiftUI
import UIKit

extension Color {
    /// App brand color. Forks rebrand by changing `brand.colorset` only — never override at call sites.
    static let brand = Color(.brand)
}

extension UIColor {
    static let brand = UIColor(resource: .brand)
    /// Speed and ping graph line/fill color; rebranded together with `brand.colorset`.
    static let graphAccent = UIColor(resource: .graphAccent)
}
