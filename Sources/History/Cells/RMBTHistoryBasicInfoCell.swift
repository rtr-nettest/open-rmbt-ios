//
//  RMBTHistoryBasicInfoCell.swift
//  RMBT
//
//  Created by Sergey Glushchenko on 09.09.2021.
//  Copyright © 2021 appscape gmbh. All rights reserved.
//

import UIKit

final class RMBTHistoryBasicInfoCell: UITableViewCell {

    static let ID = "RMBTHistoryBasicInfoCell"
    
    @IBOutlet weak var signalView: UIView!
    @IBOutlet weak var signalTitleLabel: UILabel!
    @IBOutlet weak var signalValueLabel: UILabel!
    @IBOutlet weak var signalSubtitleLabel: UILabel!
    @IBOutlet weak var signalIcon: UIImageView!
    @IBOutlet private weak var upSubtitleLabel: UILabel!
    @IBOutlet private weak var upValueLabel: UILabel!
    @IBOutlet private weak var upTitleLabel: UILabel!
    @IBOutlet weak var upIcon: UIImageView!
    @IBOutlet private weak var downSubtitleLabel: UILabel!
    @IBOutlet private weak var downValueLabel: UILabel!
    @IBOutlet private weak var downTitleLabel: UILabel!
    @IBOutlet weak var downIcon: UIImageView!
    @IBOutlet private weak var pingSubtitleLabel: UILabel!
    @IBOutlet private weak var pingValueLabel: UILabel!
    @IBOutlet private weak var pingTitleLabel: UILabel!
    @IBOutlet weak var pingIcon: UIImageView!
    
    var pingValue: String? {
        didSet {
            pingValueLabel.text = pingValue
        }
    }
    
    var downloadValue: String? {
        didSet {
            downValueLabel.text = downloadValue
        }
    }
    
    var uploadValue: String? {
        didSet {
            upValueLabel.text = uploadValue
        }
    }
    
    var signalValue: String? {
        didSet {
            signalValueLabel.text = signalValue
            signalView.isHidden = signalValue == nil
        }
    }
    
}
