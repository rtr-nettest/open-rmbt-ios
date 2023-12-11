//
//  RMBTLoopModeWaitingViewController.swift
//  RMBT
//
//  Created by Sergey Glushchenko on 02.11.2021.
//  Copyright © 2021 appscape gmbh. All rights reserved.
//

import UIKit

final class RMBTLoopModeWaitingViewController: UIViewController {
    @IBOutlet weak var orLabel: UILabel!
    
    @IBOutlet weak var locationWarningTitleLabel: UILabel!
    @IBOutlet weak var locationWarningView: UIView!
    
    lazy var distancePercentView: RMBTHistoryResultPercentView = {
        let view = RMBTHistoryResultPercentView(frame: CGRect.zero)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.percents = 0
        view.templateImage = UIImage(named:"traffic_lights_small_template")?.withRenderingMode(.alwaysTemplate)
        view.isHidden = false
        view.unfilledColor = UIColor.white.withAlphaComponent(0.4)
        view.filledColor = UIColor.white.withAlphaComponent(1.0)
        return view
    }()
    
    @IBOutlet weak var distancePercentViewContainer: UIView!
    @IBOutlet weak var distanceValueLabel: UILabel!
    @IBOutlet weak var distanceTitleLabel: UILabel!
    
    lazy var minutesPercentView: RMBTHistoryResultPercentView = {
        let view = RMBTHistoryResultPercentView(frame: CGRect.zero)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.percents = 0
        view.templateImage = UIImage(named:"traffic_lights_small_template")?.withRenderingMode(.alwaysTemplate)
        view.isHidden = false
        view.unfilledColor = UIColor.white.withAlphaComponent(0.4)
        view.filledColor = UIColor.white.withAlphaComponent(1.0)
        return view
    }()
    
    @IBOutlet weak var minutesPercentViewContainer: UIView!
    @IBOutlet weak var minutesValueLabel: UILabel!
    @IBOutlet weak var minutesTitleLabel: UILabel!
    
    public var minutesPercents: CGFloat = 0.0 {
        didSet {
            minutesPercentView.percents = minutesPercents
        }
    }
    
    public var distancePercents: CGFloat = 0.0 {
        didSet {
            distancePercentView.percents = distancePercents
        }
    }
    
    public var minutesValue: String = "" {
        didSet {
            minutesValueLabel.text = minutesValue
        }
    }
    
    public var distanceValue: String = "" {
        didSet {
            distanceValueLabel.text = distanceValue
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        initUI()
    }
    
    private func initUI() {
        orLabel.text = .orTitle
        locationWarningView.isHidden = RMBTLocationTracker.shared.isAuthorized
        locationWarningTitleLabel.text = .locationWarning
        if !RMBTLocationTracker.shared.isAuthorized {
            distanceValueLabel.text = ""
        }
        distanceTitleLabel.text = .distanceTitle
        minutesTitleLabel.text = .minuteTitle
        
        self.distancePercentViewContainer.addSubview(distancePercentView)
        NSLayoutConstraint.activate([
            distancePercentView.leftAnchor.constraint(equalTo: self.distancePercentViewContainer.leftAnchor),
            distancePercentView.topAnchor.constraint(equalTo: self.distancePercentViewContainer.topAnchor),
            distancePercentView.bottomAnchor.constraint(equalTo: self.distancePercentViewContainer.bottomAnchor),
            distancePercentView.rightAnchor.constraint(equalTo: self.distancePercentViewContainer.rightAnchor)
        ])
        
        self.minutesPercentViewContainer.addSubview(minutesPercentView)
        NSLayoutConstraint.activate([
            minutesPercentView.leftAnchor.constraint(equalTo: self.minutesPercentViewContainer.leftAnchor),
            minutesPercentView.topAnchor.constraint(equalTo: self.minutesPercentViewContainer.topAnchor),
            minutesPercentView.bottomAnchor.constraint(equalTo: self.minutesPercentViewContainer.bottomAnchor),
            minutesPercentView.rightAnchor.constraint(equalTo: self.minutesPercentViewContainer.rightAnchor)
        ])
    }
}

private extension String {
    static let orTitle = NSLocalizedString("or", comment: "")
    static let locationWarning = NSLocalizedString("loop_mode_no_gps", comment: "")
    static let distanceTitle = NSLocalizedString("loop_mode_meters", comment: "")
    static let minuteTitle = NSLocalizedString("loop_mode_minutes", comment: "")
}
