//
//  RMBTHistoryQoSGroupResultCell.swift
//  RMBT
//
//  Created by Sergey Glushchenko on 11.09.2021.
//  Copyright © 2021 appscape gmbh. All rights reserved.
//

import UIKit

final class RMBTHistoryQoSGroupResultCell: UITableViewCell {

    static let ID = "RMBTHistoryQoSGroupResultCell"
    
    @IBOutlet weak var statusDescriptionLabel: UILabel!
    @IBOutlet weak var statusLabel: UILabel!
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var descriptionLabel: UILabel!
    
    var result: RMBTHistoryQoSSingleResult? {
        didSet {
            guard let result = result else {
                return
            }
            statusLabel.text = NSLocalizedString(result.isSuccessful ? "Succeeded" : "Failed", comment: "").uppercased()
            statusLabel.textColor = result.isSuccessful ? UIColor(hex: "59B200") : .red
            statusDescriptionLabel.text = result.statusDetails
            statusDescriptionLabel.textColor = result.isSuccessful ? UIColor(hex: "59B200") : .red
        }
    }
}
