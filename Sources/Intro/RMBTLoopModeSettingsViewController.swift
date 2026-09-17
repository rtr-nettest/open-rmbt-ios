//
//  RMBTLoopModeSettingsViewController.swift
//  RMBT
//
//  Created by Sergey Glushchenko on 01.11.2021.
//  Copyright © 2021 appscape gmbh. All rights reserved.
//

import UIKit

final class RMBTLoopModeSettingsViewController: UIViewController {

    @IBOutlet weak var distanceView: UIView!
    @IBOutlet weak var minutesView: UIView!
    
    @IBOutlet weak var startTestButton: UIButton!
    @IBOutlet weak var subtitleLabel: UILabel!
    @IBOutlet weak var distanceTextField: UITextField!
    @IBOutlet weak var distanceLabel: UILabel!
    @IBOutlet weak var minutesTextField: UITextField!
    @IBOutlet weak var minutesLabel: UILabel!
    @IBOutlet weak var countTestsTextField: UITextField!
    @IBOutlet weak var paramsTitleLabel: UILabel!
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var bottomConstraint: NSLayoutConstraint!
    
    lazy var loopModeInfo: RMBTLoopInfo = {
       return RMBTLoopInfo(with: RMBTSettings.shared.loopModeEveryMeters,
                           minutes: RMBTSettings.shared.loopModeEveryMinutes,
                           total: RMBTSettings.shared.loopModeLastCount)
    }()
    var loopModeHandler: (_ loopMode: RMBTLoopInfo) -> Void = { _ in }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupUI()
        
        distanceView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(distanceTap(_:))))
        minutesView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(minutesTap(_:))))
        
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardDidChange), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
    }
    
    @objc func distanceTap(_ sender: Any) {
        distanceTextField.becomeFirstResponder()
        distanceTextField.goToEndPosition()
    }
    
    @objc func minutesTap(_ sender: Any) {
        minutesTextField.becomeFirstResponder()
        minutesTextField.goToEndPosition()
    }
    
    func setupUI() {
        navigationController?.setNavigationBarHidden(true, animated: false)
        titleLabel.text = .title
        paramsTitleLabel.text = .titleParameters
        countTestsTextField.text = String(loopModeInfo.total)
        minutesLabel.text = .minutesTitle
        minutesTextField.text = String(loopModeInfo.waitMinutes)
        distanceLabel.text = .distanceTitle
        distanceTextField.text = String(loopModeInfo.waitMeters)
        startTestButton.setTitle(.startButtonTitle, for: .normal)
        subtitleLabel.text = .subtitle
        [countTestsTextField, minutesTextField, distanceTextField].forEach { $0.tintColor = .brand.withAlphaComponent(0.4) }
    }
    
    @objc func keyboardDidChange(_ notification: Notification) {
        let userInfo = notification.userInfo
        guard let frame = userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let selfFrame = self.view.convert(self.view.frame, to: self.view.window)
        let buttonButtomOffset: CGFloat = 24
        let bottomOffset = (selfFrame.height + selfFrame.origin.y) - frame.origin.y + buttonButtomOffset
        UIView.animate(withDuration: 0.3) {
            self.bottomConstraint.constant = bottomOffset
            self.view.layoutIfNeeded()
        }
    }
    
    @IBAction func closeButtonClick(_ sender: Any) {
        self.dismiss(animated: true, completion: nil)
    }
    
    @IBAction func startButtonClick(_ sender: Any) {
        loopModeInfo.total = UInt(Int(countTestsTextField.text ?? "") ?? 0)
        loopModeInfo.waitMeters = UInt(Int(distanceTextField.text ?? "") ?? 0)
        loopModeInfo.waitMinutes = UInt(Int(minutesTextField.text ?? "") ?? 0)
        guard validate() else { return }
        store()
        dismiss(animated: true) {
            self.loopModeHandler(self.loopModeInfo)
        }
    }
    
    private func store() {
        RMBTSettings.shared.loopModeEveryMeters = loopModeInfo.waitMeters
        RMBTSettings.shared.loopModeEveryMinutes = loopModeInfo.waitMinutes
        RMBTSettings.shared.loopModeLastCount = loopModeInfo.total
    }
    
    private func validate() -> Bool {
        guard !RMBTSettings.shared.isDevModeEnabled else { return true }
        if !RMBTLoopModeSettingsValidator.validateCountTest(for: loopModeInfo) {
            let text = String(format: .pleaseEnterValueBetween, RMBTConfig.RMBT_TEST_LOOPMODE_MIN_COUNT, RMBTConfig.RMBT_TEST_LOOPMODE_MAX_COUNT)
            UIAlertController.presentCancelAlert(title: .invalideCount,
                                           text: text, { [weak self] _ in
                self?.countTestsTextField.becomeFirstResponder()
            })
            return false
        }
        
        if !RMBTLoopModeSettingsValidator.validateDuration(for: loopModeInfo) {
            let text = String(format: .pleaseEnterValueBetween, RMBTConfig.RMBT_TEST_LOOPMODE_MIN_DELAY_MINS, RMBTConfig.RMBT_TEST_LOOPMODE_MAX_DELAY_MINS)
            UIAlertController.presentCancelAlert(title: .invalideMinutes, text: text, { [weak self] _ in
                self?.minutesTextField.becomeFirstResponder()
            })
            return false
        }
        
        if !RMBTLoopModeSettingsValidator.validateDistance(for: loopModeInfo) {
            let text = String(format: .pleaseEnterValueBetween, RMBTConfig.RMBT_TEST_LOOPMODE_MIN_MOVEMENT_M, RMBTConfig.RMBT_TEST_LOOPMODE_MAX_MOVEMENT_M)
            UIAlertController.presentCancelAlert(title: .invalideDistance, text: text, { [weak self] _ in
                self?.minutesTextField.becomeFirstResponder()
            })
            return false
        }
        return true
    }
}

extension RMBTLoopModeSettingsViewController: UITextFieldDelegate {
    func textFieldDidBeginEditing(_ textField: UITextField) {
        DispatchQueue.main.async {
            textField.goToEndPosition()
        }
    }
}

private extension String {
    static let title = NSLocalizedString("title_loop_mode", comment: "")
    static let titleParameters = NSLocalizedString("title_loop_count", comment: "")
    static let minutesTitle = NSLocalizedString("preferences_loop_mode_min_delay", comment: "")
    static let distanceTitle = NSLocalizedString("preferences_loop_mode_max_movement", comment: "")
    static let subtitle = NSLocalizedString("preferences_loop_mode_summary", comment: "")
    static let startButtonTitle = NSLocalizedString("text_loop_start", comment: "")
    
    static let invalideCount = NSLocalizedString("invalide_loop_mode_count", comment: "")
    static let invalideDistance = NSLocalizedString("invalide_loop_mode_distance", comment: "")
    static let invalideMinutes = NSLocalizedString("invalide_loop_mode_waiting_minutes", comment: "")
    
    static let pleaseEnterValueBetween = NSLocalizedString("loop_mode_enter_value_between_format", comment: "")
}
