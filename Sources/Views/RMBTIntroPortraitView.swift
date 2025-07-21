//
//  RMBTIntroPortraitView.swift
//  RMBT
//
//  Created by Sergey Glushchenko on 23.10.2021.
//  Copyright 2021 appscape gmbh. All rights reserved.
//

import UIKit

class RMBTIntroPortraitView: UIView, XibLoadable {

    @IBOutlet private weak var locationImageView: UIImageView!
    @IBOutlet private weak var ipV6ImageView: UIImageView!
    @IBOutlet private weak var ipV4ImageView: UIImageView!
    @IBOutlet private weak var coverageImageView: UIImageView!
    @IBOutlet internal weak var waveView: RMBTWaveView!
    @IBOutlet internal weak var wave2View: RMBTWaveView!
    @IBOutlet internal weak var gradientView: RMBTGradientView!

    @IBOutlet private weak var networkNameLabel: UILabel!
    @IBOutlet private weak var networkTypeLabel: UILabel!
    @IBOutlet private weak var networkWifiTypeImageView: UIImageView!
    @IBOutlet private weak var networkWifiView: UIView!
    @IBOutlet private weak var networkMobileTypeImageView: UIImageView!
    @IBOutlet private weak var networkMobileClassImageView: UIImageView!
    @IBOutlet private weak var networkMobileView: UIView!

    @IBOutlet private weak var loopModeLabel: UILabel!
    @IBOutlet private weak var logoLabel: UILabel!
    @IBOutlet private weak var settingsButton: UIButton!

    @IBOutlet weak var startTestButton: UIButton!
    @IBOutlet weak var startTestButtonCircleView: UIView!
    @IBOutlet weak var loopModeSwitchButton: UIButton!
    @IBOutlet private weak var loopIconImageView: UIImageView!

    @IBOutlet private var trailingLoopModeSwitcherConstraint: NSLayoutConstraint!
    @IBOutlet private var leadingLoopModeSwitcherConstraint: NSLayoutConstraint!

    var ipV4Tapped: (_ tintColor: UIColor) -> Void = { _ in }
    var ipV6Tapped: (_ tintColor: UIColor) -> Void = { _ in }
    var locationTapped: (_ tintColor: UIColor) -> Void = { _ in }
    var coverageTapped: (_ tintColor: UIColor) -> Void = { _ in }
    var loopModeHandler: (_ isOn: Bool) -> Void = { _ in }
    var startButtonHandler: () -> Void = { }
    var settingsButtonHandler: () -> Void = { }

    var networkName: String? {
        didSet {
            self.networkNameLabel.text = networkName
        }
    }

    var isHiddenNetworkName: Bool = false {
        didSet {
            self.networkNameLabel.isHidden = isHiddenNetworkName
        }
    }

    var ipV4TintColor: UIColor? {
        didSet {
            ipV4ImageView.tintColor = ipV4TintColor
        }
    }

    var ipV6TintColor: UIColor? {
        didSet {
            ipV6ImageView.tintColor = ipV6TintColor
        }
    }

    var locationTintColor: UIColor? {
        didSet {
            locationImageView.tintColor = locationTintColor
        }
    }

    var coverageTintColor: UIColor? {
        didSet {
            coverageImageView.tintColor = coverageTintColor
        }
    }

    var networkMobileClassImage: UIImage? {
        didSet {
            networkMobileClassImageView.image = networkMobileClassImage
        }
    }

    @IBAction func startButtonClick(_ sender: Any) {
        startButtonHandler()
    }

    @IBAction func settingsButtonClick(_ sender: Any) {
        settingsButtonHandler()
    }

    @IBAction func loopModeSwitched(_ sender: Any) {
        self.loopModeSwitchButton.isSelected = !self.loopModeSwitchButton.isSelected
        self.loopModeHandler(self.loopModeSwitchButton.isSelected)
        self.updateLoopModeUI()
    }

    override func awakeFromNib() {
        super.awakeFromNib()
        self.initUI()
    }

    func initUI() {
        self.startTestButton.accessibilityLabel = .startButtonA11Label
        self.loopModeSwitchButton.accessibilityLabel = RMBTSettings.shared.loopMode ? .loopModeSwitchOnA11Label : .loopModeSwitchOffA11Label

        self.loopModeLabel.text = String.loopModeLabel

        let image = self.settingsButton.image(for: .normal)?.withRenderingMode(.alwaysTemplate)
        self.settingsButton.setImage(image, for: .normal)
        self.settingsButton.tintColor = .networkLogoAvailable
        self.settingsButton.accessibilityLabel = .settingsButtonA11Label

        self.locationImageView.image = self.locationImageView.image?.withRenderingMode(.alwaysTemplate)
        self.ipV6ImageView.image = self.ipV6ImageView.image?.withRenderingMode(.alwaysTemplate)
        self.ipV4ImageView.image = self.ipV4ImageView.image?.withRenderingMode(.alwaysTemplate)
        self.coverageImageView.image = self.coverageImageView.image?.withRenderingMode(.alwaysTemplate)

        self.ipV4ImageView.isUserInteractionEnabled = true
        self.ipV6ImageView.isUserInteractionEnabled = true
        self.locationImageView.isUserInteractionEnabled = true
        self.coverageImageView.isUserInteractionEnabled = true

        self.ipV4ImageView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(ipv4TapHandler(_:))))
        self.ipV6ImageView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(ipv6TapHandler(_:))))
        self.locationImageView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(locationTapHandler(_:))))
        self.coverageImageView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(coverageTapHandler(_:))))

        self.ipV4ImageView.isAccessibilityElement = true
        self.ipV4ImageView.accessibilityTraits = .button
        self.ipV4ImageView.accessibilityLabel = .ipv4ImageViewA11Label

        self.ipV6ImageView.isAccessibilityElement = true
        self.ipV6ImageView.accessibilityTraits = .button
        self.ipV6ImageView.accessibilityLabel = .ipv6ImageViewA11Label

        self.locationImageView.isAccessibilityElement = true
        self.locationImageView.accessibilityTraits = .button
        self.locationImageView.accessibilityLabel = .locationImageViewA11Label

        self.coverageImageView.isAccessibilityElement = true
        self.coverageImageView.accessibilityTraits = .button
        self.coverageImageView.accessibilityLabel = .coverageImageViewA11Label

        self.coverageTintColor = .ipAvailable

        waveView.startAnimation()
        waveView.direction = .backwards
        wave2View.alpha = 0.2
        wave2View.direction = .forwards
        wave2View.startAnimation()
    }

    func startAnimation() {
        waveView.startAnimation()
        wave2View.startAnimation()
    }

    func stopAnimation() {
        waveView.stopAnimation()
        wave2View.stopAnimation()
    }

    func updateLoopModeUI() {
        self.trailingLoopModeSwitcherConstraint.priority = RMBTSettings.shared.loopMode ? .defaultHigh : .defaultLow
        self.leadingLoopModeSwitcherConstraint.priority = RMBTSettings.shared.loopMode ? .defaultLow : .defaultHigh
        self.loopModeLabel.isHidden = !RMBTSettings.shared.loopMode
        self.loopIconImageView.isHidden = !RMBTSettings.shared.loopMode
        self.loopModeSwitchButton.isSelected = RMBTSettings.shared.loopMode
        self.loopModeSwitchButton.accessibilityLabel = RMBTSettings.shared.loopMode ? .loopModeSwitchOnA11Label : .loopModeSwitchOffA11Label
    }

    func networkAvailable(_ networkType: RMBTNetworkType, networkName: String?, networkDescription: String?) {
        var networkName = networkName
        var networkDescription = networkDescription

        if networkType == .cellular {
            networkName = networkDescription
            networkDescription = nil
        }

        self.loopIconImageView.isHidden = !RMBTSettings.shared.loopMode
        self.startTestButton.isHidden = false
        self.networkNameLabel.text = networkName
        self.networkTypeLabel.text = networkDescription
        self.networkWifiTypeImageView.image = .wifiAvailable
        if (networkType == .wifi) {
            self.networkWifiView.isHidden = false
            self.networkMobileView.isHidden = true
        } else if (networkType == .cellular) {
            self.networkMobileView.isHidden = false
            self.networkWifiView.isHidden = true
        }

        if (networkType == .wifi) || (networkType == .cellular) {
            UIView.animate(withDuration: 0.3) {
                self.backgroundColor = .networkAvailable
                self.gradientView.fromColor = .networkAvailable
                self.gradientView.alpha = 1.0
                self.networkNameLabel.textColor = .networkLogoAvailable
                self.networkTypeLabel.textColor = .networkTypeAvailable
                self.logoLabel.textColor = .networkLogoAvailable
                self.settingsButton.tintColor = .networkLogoAvailable
            }
            self.waveView.startAnimation()
            self.wave2View.startAnimation()
        }
    }

    func networkNotAvailable() {
        self.networkNameLabel.text = "";
        self.networkTypeLabel.text = .noNetworkAvailable
        self.networkWifiTypeImageView.image = .noNetworkAvailable
        self.startTestButton.isHidden = true
        self.networkMobileView.isHidden = true
        self.networkWifiView.isHidden = false
        self.loopIconImageView.isHidden = true

        UIView.animate(withDuration: 0.3) {
            self.backgroundColor = .noNetworkAvailable
            self.gradientView.alpha = 0.0
            self.networkNameLabel.textColor = .noNetworkLogoAvailable
            self.networkTypeLabel.textColor = .noNetworkTypeAvailable
            self.logoLabel.textColor = .noNetworkLogoAvailable
            self.settingsButton.tintColor = .noNetworkLogoAvailable
        }
        self.waveView.stopAnimation()
        self.wave2View.stopAnimation()
    }

    @objc private func ipv4TapHandler(_ sender: Any) {
        self.ipV4Tapped(self.ipV4ImageView.tintColor)
    }

    @objc private func ipv6TapHandler(_ sender: Any) {
        self.ipV6Tapped(self.ipV6ImageView.tintColor)
    }

    @objc private func locationTapHandler(_ sender: Any) {
        self.locationTapped(self.locationImageView.tintColor)
    }

    @objc private func coverageTapHandler(_ sender: Any) {
        self.coverageTapped(self.coverageImageView.tintColor)
    }
}

private extension String {
    static let noNetworkAvailable = NSLocalizedString("No network connection available", comment: "");
    static let loopModeLabel = NSLocalizedString("title_loop_mode", comment: "")
    static let startButtonA11Label = NSLocalizedString("Start measurement now", comment: "")
    static let loopModeSwitchOnA11Label = NSLocalizedString("Disable loop mode", comment: "")
    static let loopModeSwitchOffA11Label = NSLocalizedString("Enable loop mode", comment: "")
    static let settingsButtonA11Label = NSLocalizedString("Settings", comment: "")
    static let ipv4ImageViewA11Label = NSLocalizedString("Show IPv4 address", comment: "")
    static let ipv6ImageViewA11Label = NSLocalizedString("Show IPv6 address", comment: "")
    static let locationImageViewA11Label = NSLocalizedString("Show location", comment: "")
    static let coverageImageViewA11Label = NSLocalizedString("Show network coverage", comment: "")
}

private extension UIImage {
    static let noNetworkAvailable = UIImage(named: "no_internet_icon")
    static let wifiAvailable = UIImage(named: "wifi_icon")

    static let loopModeOn = UIImage(named: "loop_mode_switcher_on")
    static let loopModeOff = UIImage(named: "loop_mode_switcher_off")
}

private extension UIColor {
    static let noNetworkAvailable = UIColor(red: 242.0 / 255, green: 243.0 / 255, blue: 245.0 / 255, alpha: 1.0)
    static let networkAvailable = UIColor(red: 0.0 / 255, green: 113.0 / 255, blue: 215.0 / 255, alpha: 1.0)

    static let noNetworkTypeAvailable = UIColor(red: 66.0 / 255, green: 66.0 / 255, blue: 66.0 / 255, alpha: 0.4)
    static let networkTypeAvailable = UIColor(red: 1, green: 1, blue: 1, alpha: 0.4)

    static let noNetworkLogoAvailable = UIColor(red: 66.0 / 255, green: 66.0 / 255, blue: 66.0 / 255, alpha: 1.0)
    static let networkLogoAvailable = UIColor(red: 1, green: 1, blue: 1, alpha: 1.0)

    static let ipNotAvailable = UIColor(red: 245.0 / 255.0, green: 0.0 / 255.0, blue: 28.0/255.0, alpha: 1.0)
    static let ipSemiAvailable = UIColor(red: 255.0 / 255.0, green: 186.0 / 255.0, blue: 0, alpha: 1.0)
    static let ipAvailable = UIColor(red: 89.0 / 255.0, green: 178.0 / 255.0, blue: 0, alpha: 1.0)
}
