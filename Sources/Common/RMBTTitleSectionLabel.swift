//
//  RMBTTitleSectionLabel.swift
//  RMBT
//
//  Created by Sergey Glushchenko on 11.11.2021.
//  Copyright © 2021 appscape gmbh. All rights reserved.
//

import UIKit

class RMBTTitleSectionLabel: UILabel {

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    func setupUI() {
        self.font = UIFont.roboto(size: 14, weight: .medium)
        self.textColor = UIColor.rmbt_color(withRGBHex: 0x5F6368, alpha: 0.58)
    }
    
    @objc init(text: String) {
        self.init()
        self.text = text
    }
}
