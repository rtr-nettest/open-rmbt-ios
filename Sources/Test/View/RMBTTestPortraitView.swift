//
//  RMBTTestPortraitView.swift
//  RMBT
//
//  Created by Sergey Glushchenko on 15.11.2021.
//  Copyright © 2021 appscape gmbh. All rights reserved.
//

import UIKit

class RMBTTestPortraitView: UIView, XibLoadable {
    
    @IBOutlet weak var detailTestView: UIView!
    
    @IBOutlet weak var rootGaugeView: UIView!
    @IBOutlet weak var infoTitleView: UIView!
    @IBOutlet weak var loopModeTitleHeightConstraint: NSLayoutConstraint!
    @IBOutlet weak var loopModeCounterLoaderView: RMBTLoaderView!
    @IBOutlet weak var loopModeCounterLabel: UILabel!
    @IBOutlet weak var loopModeCounterView: UIView!
    @IBOutlet weak var loopModeTitleLabel: UILabel!
    @IBOutlet weak var loopModeTitleView: UIView!
    
    @IBOutlet weak var offsetGaugesConstraint: NSLayoutConstraint!
    @IBOutlet weak var aspectGaugesConstraint: NSLayoutConstraint!
    
    @IBOutlet weak var infoTitleHeightConstraint: NSLayoutConstraint!

    // Network name and type
    @IBOutlet weak var technologyTitleLabel: UILabel!
    @IBOutlet weak var technologyValueLabel: UILabel!
    @IBOutlet weak var networkTypeLabel: UILabel?
    @IBOutlet weak var networkNameTitleLabel: UILabel!
    @IBOutlet weak var networkNameLabel: UILabel!
    @IBOutlet weak var networkTypeImageView: UIImageView!
    
    @IBOutlet weak var networkMobileImageView: UIImageView!
    @IBOutlet weak var networkTechnologyImageView: UIImageView!
    
    @IBOutlet weak var infoView: UIView!
    @IBOutlet weak var bottomSpeedConstraint: NSLayoutConstraint!
    
    @IBOutlet weak var counterAnimationView: RMBTLoaderView!
    @IBOutlet weak var counterLabel: UILabel!
    @IBOutlet weak var counterView: UIView!
    // Progress
    @IBOutlet weak var progressLabel: UILabel!
    @IBOutlet weak var progressGaugePlaceholderView: UIImageView!

    // Results
    @IBOutlet weak var pingIconImageView: UIImageView!
    @IBOutlet weak var pingResultLabel: UILabel!
    @IBOutlet weak var downIconImageView: UIImageView!
    @IBOutlet weak var downResultLabel: UILabel!
    @IBOutlet weak var upIconImageView: UIImageView!
    @IBOutlet weak var upResultLabel: UILabel!

    // Speed chart
    @IBOutlet weak var speedGaugePlaceholderView: UIImageView!
    @IBOutlet weak var pingGraphView: RMBTPingGraphView!
    @IBOutlet weak var speedGraphView: RMBTSpeedGraphView!
    @IBOutlet weak var arrowImageView: UIImageView!
    @IBOutlet weak var speedLabel: UILabel!
    @IBOutlet weak var speedSuffixLabel: UILabel!

    // Footer
    @IBOutlet weak var statusLabel: UILabel!
    @IBOutlet weak var footerTestServerLabel: UILabel?
    @IBOutlet weak var footerLocalIpLabel: UILabel?
    @IBOutlet weak var footerLocationLabel: UILabel?
    
    // QoS
    @IBOutlet weak var qosProgressView: UIView!
    @IBOutlet weak var qosProgressLabelContainer: UIStackView!

    // Loop Mode Waiting
    @IBOutlet weak var loopModeWaitingView: UIView!
    
    // Layout constraints
    @IBOutlet weak var networkSymbolTopConstraint: NSLayoutConstraint!
    @IBOutlet weak var networkSymbolLeftConstraint: NSLayoutConstraint!
    @IBOutlet weak var networkNameWidthConstraint: NSLayoutConstraint!
    @IBOutlet weak var testServerLabelHeightConstraint: NSLayoutConstraint!
    @IBOutlet weak var speedGraphBottomConstraint: NSLayoutConstraint!
    @IBOutlet weak var progressGaugeTopConstraint: NSLayoutConstraint!
    @IBOutlet weak var footerBottomConstraint: NSLayoutConstraint!
    @IBOutlet var detailInfoHeightConstraint: NSLayoutConstraint?
    
    // Views
    lazy var speedGaugeView: RMBTGaugeView = {
        return RMBTGaugeView(frame: self.speedGaugePlaceholderView.frame, name: "speed", startAngle: 29, endAngle: 295.0)
    }()
    
    lazy var progressGaugeView: RMBTGaugeView = {
        return RMBTGaugeView(frame: self.progressGaugePlaceholderView.frame, name: "progress", startAngle: 215.0, endAngle: 215.0 + 280.0)
    }()
    
    var networkName: String? {
        didSet {
            self.networkNameLabel.text = networkName
            self.networkNameTitleLabel.isHidden = (networkName?.isEmpty ?? true)
        }
    }
    
    var networkType: String? {
        didSet {
            self.networkTypeLabel?.text = networkType
        }
    }
    
    var networkTypeImage: UIImage? {
        didSet {
            self.networkTypeImageView.image = networkTypeImage
        }
    }
    
    var networkTypeEnum: RMBTNetworkType? {
        didSet {
            self.networkTypeImageView.isHidden = true
            self.networkMobileImageView.isHidden = true
            self.networkTechnologyImageView.isHidden = true
            
            if let networkType = networkTypeEnum {
                if networkType == .cellular {
                    self.networkMobileImageView.isHidden = false
                    self.networkTechnologyImageView.isHidden = false
                } else {
                    self.networkTypeImageView.isHidden = false
                }
            }
        }
    }
    
    var networkTypeTechnology: RMBTNetworkTypeConstants.NetworkType? {
        didSet {
            if self.networkTypeTechnology != .wlan {
                self.networkTechnologyImageView.image = self.networkTypeTechnology?.technologyIcon?.withRenderingMode(.alwaysTemplate)
            }
        }
    }
    
    var technology: String? {
        didSet {
            self.technologyValueLabel.text = technology
        }
    }
    
    var status: String? {
        didSet {
            self.statusLabel.text = status
        }
    }
    
    var progress: UInt = 0 {
        didSet {
            self.progressLabel.text = "\(progress)"
        }
    }
    
    var progressGauge: Double = 0 {
        didSet {
            self.progressGaugeView.value = progressGauge
        }
    }
    
    var speed: UInt32 = 0 {
        didSet {
            self.speedLabel.text = RMBTSpeedMbpsString(Double(speed), withMbps: false)
        }
    }
    
    var speedGauge: Double = 0 {
        didSet {
            self.speedGaugeView.value = speedGauge
        }
    }

    var pingIcon: UIImage? {
        didSet {
            self.pingIconImageView.image = pingIcon
        }
    }
    
    var ping: String? {
        didSet {
            self.pingResultLabel.text = ping
        }
    }
    
    var downIcon: UIImage? {
        didSet {
            self.downIconImageView.image = downIcon
        }
    }
    
    var down: String? {
        didSet {
            self.downResultLabel.text = down
        }
    }

    var upIcon: UIImage? {
        didSet {
            self.upIconImageView.image = upIcon
        }
    }
    
    var up: String? {
        didSet {
            self.upResultLabel.text = up
        }
    }
    
    var isLoopMode: Bool = false {
        didSet {
            updateInfoTitleView()
        }
    }
    
    var onCloseHandler: () -> Void = {}
    
    var isInfoCollapsed = true {
        didSet {
            updateDetailInfoView()
        }
    }
    
    var isQOSState = false {
        didSet {
            self.counterView.isHidden = !isQOSState
        }
    }
    
    var currentTest: UInt = 0 {
        didSet {
            updateInfoTitleView()
        }
    }
    
    var totalTests: UInt = 0 {
        didSet {
            updateInfoTitleView()
        }
    }
    
    var phase: RMBTTestRunnerPhase = .none {
        didSet {
            updatePhase()
        }
    }
    
    var isShowSpeedSuffix: Bool = false {
        didSet {
            self.speedSuffixLabel.isHidden = isShowSpeedSuffix
        }
    }
    
    var qosCounterText: String? {
        didSet {
            self.counterLabel.text = qosCounterText
        }
    }
    
    @IBAction func closeButtonClick(_ sender: Any) {
        onCloseHandler()
    }
    
    func startAnimation() {
        self.loopModeCounterLoaderView.isAnimating = true
        self.counterAnimationView.isAnimating = true
    }
    
    @objc func showQoSUI(_ shouldShowQoS: Bool) {
        self.speedGraphView.isHidden = shouldShowQoS
        self.pingGraphView.isHidden = shouldShowQoS
    //    _speedGaugeView.hidden = state
        self.speedLabel.isHidden = shouldShowQoS
        self.qosProgressLabelContainer.isHidden = !shouldShowQoS
        self.speedSuffixLabel.isHidden = shouldShowQoS
        self.speedGaugeView.value = 0.0
        self.speedSuffixLabel.isHidden = shouldShowQoS
        self.arrowImageView.isHidden = shouldShowQoS
        self.qosProgressView.isHidden = !shouldShowQoS
        if shouldShowQoS == false {
            self.updatePhase()
        }
    }
    
    @objc func showWaitingUI() {
        self.loopModeWaitingView.isHidden = false
        self.pingGraphView.isHidden = true
        self.speedGraphView.isHidden = true
        self.qosProgressView.isHidden = true
        self.speedGaugeView.value = 0.0
        self.progressGaugeView.value = 0.0
        self.speedLabel.text = "--"
        self.qosProgressLabelContainer.isHidden = true
        self.progressLabel.text = "--"
        self.speedSuffixLabel.isHidden = true
    }
    
    func setQosView(_ view: UIView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        self.qosProgressView.addSubview(view)
        NSLayoutConstraint.activate([
            view.leftAnchor.constraint(equalTo: self.qosProgressView.leftAnchor),
            view.rightAnchor.constraint(equalTo: self.qosProgressView.rightAnchor),
            view.topAnchor.constraint(equalTo: self.qosProgressView.topAnchor),
            view.bottomAnchor.constraint(equalTo: self.qosProgressView.bottomAnchor),
        ])
    }
    
    func setWaitingView(_ view: UIView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        self.loopModeWaitingView.addSubview(view)
        NSLayoutConstraint.activate([
            view.leftAnchor.constraint(equalTo: self.loopModeWaitingView.leftAnchor),
            view.rightAnchor.constraint(equalTo: self.loopModeWaitingView.rightAnchor),
            view.topAnchor.constraint(equalTo: self.loopModeWaitingView.topAnchor),
            view.bottomAnchor.constraint(equalTo: self.loopModeWaitingView.bottomAnchor),
        ])
    }
    
    func clearValues() {
        self.showQoSUI(false) // in case we're restarting because test was cancelled in qos phase
        loopModeWaitingView.isHidden = true
        
        self.ping = "-"
        self.down = "-"
        self.up = "-"
        self.upIcon = .uploadIconByResultClass(nil)
        self.downIcon = .downloadIconByResultClass(nil)
        self.pingIcon = .pingIconByResultClass(nil)

        self.arrowImageView.image = nil

        speedGaugeView.value = 0.0
        self.speedLabel.text = ""
        self.qosProgressLabelContainer.isHidden = true
        self.speedSuffixLabel.isHidden = true
        self.speedGraphView.clear()
        self.pingGraphView.clear()
        
        self.updateInfoTitleView()
    }
    
    func updateInfoTitleView() {
        infoTitleHeightConstraint.constant = !isLoopMode ? 63 : 111
        loopModeTitleHeightConstraint.constant = !isLoopMode ? 0 : 48
        loopModeTitleView.isHidden = !isLoopMode
        loopModeTitleLabel.text = .loopMode
        loopModeCounterLabel.text = "\(currentTest)/\(totalTests)"
    }
    
    @objc func updateDetailInfoView() {
        if (isInfoCollapsed) {
            UIView.animate(withDuration: 0.3) {
                let height: CGFloat = self.isQOSState ? 267 : 195
                self.detailInfoHeightConstraint?.constant = height
                self.bottomSpeedConstraint.constant = 0
                self.layoutIfNeeded()
            }
        } else {
            UIView.animate(withDuration: 0.3) {
                let offset = self.detailInfoHeightConstraint?.constant ?? 0
                self.bottomSpeedConstraint.constant = -(offset + self.safeAreaInsets.bottom)
                self.layoutIfNeeded()
            }
        }
    }
    
    @objc func infoViewTap() {
        isInfoCollapsed = !isInfoCollapsed
    }
    
    func clearSpeedGraph() {
        self.speedGraphView.clear()
    }
    
    func clearPingGraph() {
        self.pingGraphView.clear()
    }
    
    func addSpeed(_ value: CGFloat, at timeinterval: TimeInterval) {
        self.speedGraphView.add(value: value, at: timeinterval)
    }
    
    func addPing(_ value: CGFloat, at timeinterval: TimeInterval) {
        self.pingGraphView.add(value: value, at: timeinterval)
    }
    
    func updatePhase() {
        if (phase == .down) {
            self.speedGraphView.isHidden = false
            self.arrowImageView.image = UIImage(named: "download_icon")
        } else if (phase == .up) || (phase == .initUp) {
            self.speedGraphView.isHidden = false
            self.speedGraphView.clear()
            self.speedLabel.text = ""
            self.qosProgressLabelContainer.isHidden = true
            self.speedSuffixLabel.isHidden = true
            self.arrowImageView.image = UIImage(named: "upload_icon")
        } else {
            self.speedGraphView.isHidden = true
        }
        
        self.pingGraphView.isHidden = true
        self.updateDetailInfoView()
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
        
        self.insertSubview(progressGaugeView, belowSubview:self.progressLabel)
        self.insertSubview(speedGaugeView, belowSubview:self.progressLabel)
        
        self.progressGaugePlaceholderView.isHidden = true
        self.speedGaugePlaceholderView.isHidden = true
        self.qosProgressLabelContainer.isHidden = true

        self.updateDetailInfoView()
        
        self.infoTitleView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(infoViewTap)))
        
        self.infoView.layer.shadowOffset = CGSize(width: 0, height: 1)
        self.infoView.layer.shadowColor = UIColor.black.cgColor
        self.infoView.layer.shadowOpacity = 0.2
        self.infoView.layer.shadowRadius = 3
        
        self.networkMobileImageView.image = self.networkMobileImageView.image?.withRenderingMode(.alwaysTemplate)

        pingGraphView.showBarChart = true
    }
    
    func updateGaugesPosition() {
        let originalOffsetScreenWidth: CGFloat = 375
        let originalOffsetConstraint: CGFloat = -85
        let offsetAspect = self.frame.width / originalOffsetScreenWidth
        self.offsetGaugesConstraint.constant = originalOffsetConstraint * offsetAspect
        
        let originalScreenWidth: CGFloat = 375
        let originalConstraint: CGFloat = -39
        let aspect = originalScreenWidth / self.frame.width
        self.aspectGaugesConstraint.constant = originalConstraint * aspect
        self.progressGaugeView.frame = self.progressGaugePlaceholderView.frame
        self.speedGaugeView.frame = self.speedGaugePlaceholderView.frame
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        updateGaugesPosition()
    }
}

private extension String {
    static let loopMode = NSLocalizedString("title_loop_mode", comment: "")
}

