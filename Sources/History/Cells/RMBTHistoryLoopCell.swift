//
//  RMBTHistoryLoopCell.swift
//  RMBT
//
//  Created by Polina Gurina on 12.11.2021.
//  Copyright © 2021 appscape gmbh. All rights reserved.
//

import UIKit

class RMBTHistoryLoopCell: UITableViewHeaderFooterView {
    static let ID = "RMBTHistoryLoopCell"
    
    var onExpand: (()->Void)?
    
    @IBOutlet weak var typeImageView: UIImageView!
    @IBOutlet weak var dateLabel: UILabel!
    @IBOutlet weak var subtitleLabel: UILabel!
    @IBOutlet weak var pointsLabel: UILabel!
    @IBOutlet weak var expandButton: UIButton!
    @IBOutlet weak var stackView: UIStackView!
    @IBOutlet weak var topBorder: UIView!
    @IBOutlet weak var bottomBorder: UIView!
    
    private var expanded = false
    
    @IBAction func expand(_ sender: UIButton) {
        UIView.animate(withDuration: 0.2) {
            self.expandButton.imageView!.transform = self.expandButton.imageView!.transform.rotated(by: .pi)
            self.expanded = !self.expanded
            if self.expanded {
                self.expandButton.accessibilityLabel = .expandButtonExpanded
            } else {
                self.expandButton.accessibilityLabel = .expandButtonCollapsed
            }
            self.layoutIfNeeded()
        }
        onExpand?()
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(expand(_:)))
        self.stackView.addGestureRecognizer(tapGesture)
        self.expandButton.accessibilityLabel = .expandButtonCollapsed
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        addSubview(topBorder)
        addSubview(bottomBorder)
    }
}

private extension String {
    static let expandButtonExpanded = NSLocalizedString("Collapse results", comment: "")
    static let expandButtonCollapsed = NSLocalizedString("Expand results", comment: "")
}
