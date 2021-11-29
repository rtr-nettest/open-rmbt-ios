//
//  RMBTTestLandscapeView.swift
//  RMBT
//
//  Created by Sergey Glushchenko on 15.11.2021.
//  Copyright © 2021 appscape gmbh. All rights reserved.
//

import UIKit

class RMBTTestLandscapeView: RMBTTestPortraitView {
    @IBOutlet weak var rootWaitingView: UIScrollView!
    @objc override func updateDetailInfoView() {
        UIView.animate(withDuration: 0.3) {
            let height: CGFloat = self.isLoopMode ? 165 : (165 + 48)
            self.detailInfoHeightConstraint?.constant = height
            self.bottomSpeedConstraint.constant = 0
            self.layoutIfNeeded()
        }
    }
    
    override func updateGaugesPosition() {
        self.progressGaugeView.frame = self.progressGaugePlaceholderView.frame
        self.speedGaugeView.frame = self.speedGaugePlaceholderView.frame
    }
    
    override func clearValues() {
        self.rootWaitingView.isHidden = true
        super.clearValues()
    }
    
    @objc override func showQoSUI(_ state: Bool) {
        super.showQoSUI(state)
        rootWaitingView.isHidden = true
    }
    
    @objc override func showWaitingUI() {
        rootWaitingView.isHidden = false
        super.showWaitingUI()
    }
}
