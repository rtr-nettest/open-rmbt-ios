//
//  RMBTHistoryIndexCell.swift
//  RMBT
//
//  Created by Sergey Glushchenko on 04.09.2021.
//  Copyright © 2021 appscape gmbh. All rights reserved.
//

import UIKit

@objc final class RMBTHistoryIndexCell: UITableViewCell {

    static let ID = "RMBTHistoryIndexCell"
    
    @IBOutlet weak var typeImageView: UIImageView!
    
    @IBOutlet weak var dateLabel: UILabel!
    
    @IBOutlet weak var downloadSpeedLabel: UILabel!
    @IBOutlet weak var downloadSpeedIcon: UIImageView!
    @IBOutlet weak var uploadSpeedLabel: UILabel!
    @IBOutlet weak var uploadSpeedIcon: UIImageView!
    @IBOutlet weak var pingLabel: UILabel!
    @IBOutlet weak var pingIcon: UIImageView!
    @IBOutlet weak var leftPaddingConstraint: NSLayoutConstraint?
    @IBOutlet weak var bottomBorder: UIView!
}
