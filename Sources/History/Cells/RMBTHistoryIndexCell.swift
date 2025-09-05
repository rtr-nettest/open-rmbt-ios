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
    @IBOutlet weak var downloadSpeedView: UIView!
    @IBOutlet weak var uploadSpeedView: UIView!
    @IBOutlet weak var pingView: UIView!
    @IBOutlet weak var coverageLabel: UILabel!
    
    func configureAsSpeedTest(with result: RMBTHistoryResult) {
        let networTypeIcon = RMBTNetworkTypeConstants.networkTypeDictionary[result.networkTypeServerDescription]?.icon
        typeImageView.image = networTypeIcon
        dateLabel.text = result.timeStringIn24hFormat
        downloadSpeedLabel.text = result.downloadSpeedMbpsString
        downloadSpeedIcon.image = .downloadIconByResultClass(result.downloadSpeedClass)
        uploadSpeedLabel.text = result.uploadSpeedMbpsString
        uploadSpeedIcon.image = .uploadIconByResultClass(result.downloadSpeedClass)
        pingLabel.text = result.shortestPingMillisString
        pingIcon.image = .pingIconByResultClass(result.pingClass)
        
        downloadSpeedView.isHidden = false
        uploadSpeedView.isHidden = false
        pingView.isHidden = false
        
        // Hide coverage label for speed tests
        coverageLabel.isHidden = true
    }
    
    func configureAsCoverageTest(with item: HistoryItem, isLoop: Bool = false) {
        if let coverageIcon = UIImage(named: "tab_coverage") {
            typeImageView.image = coverageIcon
            // Apply dark grey color to match other icons like 4G icon
            typeImageView.tintColor = UIColor.darkGray
        }
        
        // Use the exact same date format as speed tests
        if let timestamp = item.time {
            let date = Date(timeIntervalSince1970: Double(timestamp) / 1000.0)
            let formatter = DateFormatter()
            formatter.dateFormat = "dd.MM.yy, HH:mm:ss"
            dateLabel.text = formatter.string(from: date)
        } else {
            dateLabel.text = item.timeString
        }
        
        if isLoop {
            downloadSpeedLabel.text = "Coverage loop"
            downloadSpeedIcon.image = UIImage(systemName: "chevron.down")
            
            // Hide upload/ping for loop, keep download view visible
            downloadSpeedView.isHidden = false
            uploadSpeedView.isHidden = true
            pingView.isHidden = true
            coverageLabel.isHidden = true
        } else {
            // For individual coverage tests, hide speed test columns and show coverage label
            downloadSpeedView.isHidden = true
            uploadSpeedView.isHidden = true
            pingView.isHidden = true
            
            // Use dedicated coverage label with proper space
            if let count = item.fencesCount {
                coverageLabel.text = "\(count) Points"
            } else {
                coverageLabel.text = "Coverage"
            }
            coverageLabel.isHidden = false
        }
    }
}
