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

    var isCoverageEnabled: Bool = false {
        didSet {
            coverageImageView.isUserInteractionEnabled = isCoverageEnabled
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

        // Start with no mobile-class badge; the controller sets the real technology
        // icon (or clears it) once connectivity is resolved. Avoids briefly showing a
        // stale "3G" placeholder before the actual radio technology is known.
        self.networkMobileClassImageView.image = nil

        // Start the IPv4/IPv6/location indicators in a neutral grey ("not yet available")
        // instead of the inherited blue tint. The controller replaces these with the real
        // green/yellow/red status once connectivity is resolved.
        self.ipV4TintColor = .statusUnknown
        self.ipV6TintColor = .statusUnknown
        self.locationTintColor = .statusUnknown

        self.coverageTintColor = .coverageUnavailable

        // Hidden feature: Network Coverage entry point visibility
        updateCoverageUI()

        installLiquidGlassIconBar()

        waveView.startAnimation()
        waveView.direction = .backwards
        wave2View.alpha = 0.2
        wave2View.direction = .forwards
        wave2View.startAnimation()
    }

    /// Measured metrics of the iOS 26 floating Liquid Glass tab bar pill (iPhone, portrait): the visible
    /// pill is inset ~21pt from each screen edge and is ~62pt tall. The status capsule matches these so the
    /// two rows share the same width/height, and the icons are re-centred onto the tab items (layoutSubviews).
    private static let tabBarPillSideInset: CGFloat = 21
    private static let tabBarPillHeight: CGFloat = 62

    // The icon stack's leading/trailing constraints (from the XIB); layoutSubviews slides the icon columns
    // onto the tab-item centres by updating their constants. Non-nil only for the portrait icon bar.
    private var iconStackLeadingConstraint: NSLayoutConstraint?
    private var iconStackTrailingConstraint: NSLayoutConstraint?

    // The X centres of the tab-bar items, in this view's coordinates, fed by the controller once the tab bar
    // is laid out. Used to place the status icons exactly under their tab items (the items are not on even
    // pill-quarters). Nil until known / off iOS 26 → layoutSubviews falls back to an even-quarter estimate.
    private var tabItemCentersX: [CGFloat]?

    /// From iOS 26 the system tab bar renders as a floating Liquid Glass element. The intro screen's
    /// own status-icon strip (IPv4 / IPv6 / Location / Coverage) used to be an opaque `systemBackground`
    /// slab sitting directly above it, so two stacked bars — one opaque, one glass — looked disjointed.
    /// Here we drop the opaque slab and float the icon cluster inside a single Liquid Glass capsule, so
    /// the strip belongs to the same design language as the tab bar. Works for both orientations (a wide
    /// pill in portrait, a tall pill in landscape). Pre-26 keeps the original opaque bar untouched.
    private func installLiquidGlassIconBar() {
        guard #available(iOS 26.0, *) else { return }

        // The four status icons live in a stack view; its superview is the opaque container slab,
        // itself sitting at the bottom of the wave band (`waveView.superview`).
        guard let iconStack = locationImageView.superview as? UIStackView,
              let container = iconStack.superview,
              let waveBand = waveView.superview else { return }

        // Remove the opaque slab so the backdrop (below) shows through behind the floating glass.
        container.backgroundColor = .clear

        // Untinted glass so the capsule reads white, matching the white tab bar below it. The contrast
        // that a white-on-white pill previously lacked now comes from the pale-blue page behind it (the
        // wave / backdrop, tinted below), against which both white button rows stand out.
        let glassView = UIVisualEffectView(effect: UIGlassEffect(style: .regular))
        glassView.translatesAutoresizingMaskIntoConstraints = false
        glassView.cornerConfiguration = .capsule()
        // Decorative background only — the icons above keep handling their own taps.
        glassView.isUserInteractionEnabled = false
        // Behind the icons so their status tint colours stay at full strength (not blurred by the glass).
        container.insertSubview(glassView, belowSubview: iconStack)

        if iconStack.axis == .horizontal {
            // Match the tab bar pill exactly: same side margins and height, so the two rows are identical
            // in width and height. (The icons are re-centred onto the tab items in layoutSubviews.)
            NSLayoutConstraint.activate([
                glassView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Self.tabBarPillSideInset),
                glassView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Self.tabBarPillSideInset),
                glassView.centerYAnchor.constraint(equalTo: iconStack.centerYAnchor),
                glassView.heightAnchor.constraint(equalToConstant: Self.tabBarPillHeight),
            ])

            // Capture the stack's own leading/trailing constraints (from the XIB) so layoutSubviews can
            // slide the icon columns inward until each icon sits on its tab item's centre.
            for c in container.constraints {
                if c.firstItem === iconStack, c.firstAttribute == .leading, c.secondAttribute == .leading {
                    iconStackLeadingConstraint = c
                } else if c.secondItem === iconStack, c.secondAttribute == .trailing, c.firstAttribute == .trailing {
                    iconStackTrailingConstraint = c
                }
            }

            // Portrait only: the status capsule and the system tab bar both float over the bottom of the
            // screen. Extend the page all the way down — from the wave's bottom edge to the very bottom of
            // the view, behind the tab bar. Tint the wave fill and this backdrop the same pale blue so the
            // white glass capsule and white tab bar read as distinct button rows floating on it (a plain
            // white page made them blend). The wave and backdrop share one colour to avoid a visible seam
            // where they meet. Inserted beneath the wave band so the waves / icons / glass stay on top.
            // (Landscape's icon strip is a side column, not a bottom band, so this backdrop is portrait-only.)
            waveView.color = .introBottomPage
            wave2View.color = .introBottomPage
            let backdrop = UIView()
            backdrop.translatesAutoresizingMaskIntoConstraints = false
            backdrop.backgroundColor = .introBottomPage
            insertSubview(backdrop, belowSubview: waveBand)
            NSLayoutConstraint.activate([
                // `container.topAnchor` == the wave band's bottom edge, where the wave fill is solid.
                backdrop.topAnchor.constraint(equalTo: container.topAnchor),
                backdrop.bottomAnchor.constraint(equalTo: bottomAnchor),
                backdrop.leadingAnchor.constraint(equalTo: leadingAnchor),
                backdrop.trailingAnchor.constraint(equalTo: trailingAnchor),
            ])
        } else {
            // Landscape: a tall pill hugging the side icon column (a little padding top/bottom, fixed width).
            let alongAxisPadding: CGFloat = 16
            let crossAxisThickness: CGFloat = 64
            NSLayoutConstraint.activate([
                glassView.topAnchor.constraint(equalTo: iconStack.topAnchor, constant: -alongAxisPadding),
                glassView.bottomAnchor.constraint(equalTo: iconStack.bottomAnchor, constant: alongAxisPadding),
                glassView.centerXAnchor.constraint(equalTo: iconStack.centerXAnchor),
                glassView.widthAnchor.constraint(equalToConstant: crossAxisThickness),
            ])
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        alignIconRowToTabBarItems()
    }

    /// The controller reports the tab-bar items' X centres here (in this view's coordinates) once the tab
    /// bar is laid out, so the status icons can be placed exactly beneath them. Triggers a re-layout only
    /// when the values actually change, to avoid a layout loop.
    func setTabItemCentersX(_ centers: [CGFloat]?) {
        guard tabItemCentersX != centers else { return }
        tabItemCentersX = centers
        // Apply right away with the current bounds; the constraint change schedules the visual update. (A
        // plain setNeedsLayout() would not re-run the alignment reliably within the same layout cycle.)
        alignIconRowToTabBarItems()
    }

    /// Slides the status icons so each sits on the centre of its corresponding tab-bar item below. With the
    /// stack's `equalSpacing` distribution, pinning the outer columns to the outer tab-item centres makes the
    /// evenly-spaced items in between line up too. Uses the real item centres reported by the controller when
    /// available; otherwise falls back to an even-quarter estimate of the tab bar pill. No-op unless the
    /// portrait icon bar was installed (iOS 26). Recomputed on every layout so it stays correct across widths.
    private func alignIconRowToTabBarItems() {
        guard let leading = iconStackLeadingConstraint,
              let trailing = iconStackTrailingConstraint,
              let iconStack = locationImageView.superview as? UIStackView,
              !iconStack.arrangedSubviews.isEmpty else { return }

        let width = bounds.width
        guard width > 0 else { return }

        let iconWidth = locationImageView.bounds.width > 0 ? locationImageView.bounds.width : 45
        // Number of icons the stack actually lays out (UIStackView ignores hidden arranged subviews).
        let visibleIconCount = iconStack.arrangedSubviews.filter { !$0.isHidden }.count

        let leadingInset: CGFloat
        let trailingInset: CGFloat
        if let centers = tabItemCentersX,
           centers.count == visibleIconCount,
           let first = centers.first, let last = centers.last,
           isStrictlyIncreasing(centers), first >= 0, last <= width {
            // Exact: outer icons onto the outer tab-item centres; equalSpacing handles the ones between.
            leadingInset = first - iconWidth / 2
            trailingInset = width - last - iconWidth / 2
        } else {
            // Fallback estimate: centre the icons on even segments of the tab bar pill.
            let segment = (width - 2 * Self.tabBarPillSideInset) / CGFloat(max(visibleIconCount, 1))
            leadingInset = Self.tabBarPillSideInset + segment / 2 - iconWidth / 2
            trailingInset = leadingInset
        }

        if abs(leading.constant - leadingInset) > 0.5 { leading.constant = leadingInset }
        if abs(trailing.constant - trailingInset) > 0.5 { trailing.constant = trailingInset }
    }

    private func isStrictlyIncreasing(_ values: [CGFloat]) -> Bool {
        zip(values, values.dropFirst()).allSatisfy { $0 < $1 }
    }

    func startAnimation() {
        waveView.startAnimation()
        wave2View.startAnimation()
    }

    func stopAnimation() {
        waveView.stopAnimation()
        wave2View.stopAnimation()
    }

    // MARK: - Feature flags
    func updateCoverageUI() {
        // Hide the Coverage button unless explicitly enabled via secret code
        self.coverageImageView.isHidden = !RMBTSettings.shared.coverageFeatureEnabled
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
        let resolved = Self.resolveNetworkLabels(
            networkType: networkType,
            networkName: networkName,
            networkDescription: networkDescription
        )

        self.loopIconImageView.isHidden = !RMBTSettings.shared.loopMode
        self.startTestButton.isHidden = false
        self.networkNameLabel.text = resolved.networkName
        self.networkTypeLabel.text = resolved.networkDescription
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

    static func resolveNetworkLabels(
        networkType: RMBTNetworkType,
        networkName: String?,
        networkDescription: String?
    ) -> (networkName: String?, networkDescription: String?) {
        var networkName = networkName
        var networkDescription = networkDescription

        if networkType == .cellular {
            networkName = networkDescription
            networkDescription = nil
        } else if networkType == .wifi, (networkName ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            networkName = networkDescription
            networkDescription = nil
        }

        return (networkName: networkName, networkDescription: networkDescription)
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
    static let coverageImageViewA11Label = NSLocalizedString("Show Signal Measurement", comment: "")
}

private extension UIImage {
    static let noNetworkAvailable = UIImage(named: "no_internet_icon")
    static let wifiAvailable = UIImage(named: "wifi_icon")

    static let loopModeOn = UIImage(named: "loop_mode_switcher_on")
    static let loopModeOff = UIImage(named: "loop_mode_switcher_off")
}

extension UIColor {
    /// The pale-blue "page" colour for the intro screen's bottom area on iOS 26 (Liquid Glass): the wave
    /// fill, the backdrop below it, and the strip behind the tab bar (see RMBTIntroViewController) all use
    /// it. A little blue so the white status capsule and white tab bar read as distinct rows floating on it.
    static let introBottomPage = UIColor(red: 0.82, green: 0.89, blue: 0.97, alpha: 1.0)
}

private extension UIColor {
    static let noNetworkAvailable = UIColor(red: 242.0 / 255, green: 243.0 / 255, blue: 245.0 / 255, alpha: 1.0)
    static let networkAvailable = UIColor(red: 0.0 / 255, green: 113.0 / 255, blue: 215.0 / 255, alpha: 1.0)

    static let noNetworkTypeAvailable = UIColor(red: 66.0 / 255, green: 66.0 / 255, blue: 66.0 / 255, alpha: 0.4)
    static let networkTypeAvailable = UIColor(red: 1, green: 1, blue: 1, alpha: 0.4)

    static let noNetworkLogoAvailable = UIColor(red: 66.0 / 255, green: 66.0 / 255, blue: 66.0 / 255, alpha: 1.0)
    static let networkLogoAvailable = UIColor(red: 1, green: 1, blue: 1, alpha: 1.0)

    static let statusUnknown = UIColor.systemGray
    static let ipNotAvailable = UIColor(red: 245.0 / 255.0, green: 0.0 / 255.0, blue: 28.0/255.0, alpha: 1.0)
    static let ipSemiAvailable = UIColor(red: 255.0 / 255.0, green: 186.0 / 255.0, blue: 0, alpha: 1.0)
    static let ipAvailable = UIColor(red: 89.0 / 255.0, green: 178.0 / 255.0, blue: 0, alpha: 1.0)
    static let coverageUnavailable = UIColor.systemGray
}
