//
//  RMBTSettingsViewController.swift
//  RMBT
//
//  Created by Sergey Glushchenko on 27.10.2021.
//  Copyright © 2021 appscape gmbh. All rights reserved.
//

import Foundation
import UIKit
import libextobjc
import MessageUI

enum RMBTSettingsSection: Int {
    case general = 0
    case advanced
    case contacts
    case info
    case support
    case debug
    case debugCustomControlServer
    case logging
}

protocol RMBTSettingsViewControllerDelegate: AnyObject {
    func settingsDidChanged(in viewController: RMBTSettingsViewController)
}

class RMBTSettingsViewController: UITableViewController {
    @IBOutlet weak var forceIPv4Switch: UISwitch!
    @IBOutlet weak var skipQoSSwitch: UISwitch!
    @IBOutlet weak var expertModeSwitch: UISwitch!
    
    @IBOutlet weak var loopModeSwitch: UISwitch!
    @IBOutlet weak var loopModeWaitTextField: UITextField!
    @IBOutlet weak var loopModeDistanceTextField: UITextField!

    @IBOutlet weak var debugForceIPv6Switch: UISwitch!
    @IBOutlet weak var debugControlServerCustomizationEnabledSwitch: UISwitch!
    @IBOutlet weak var debugControlServerHostnameTextField: UITextField!
    @IBOutlet weak var debugControlServerPortTextField: UITextField!
    @IBOutlet weak var debugControlServerUseSSLSwitch: UISwitch!

    @IBOutlet weak var debugLoggingEnabledSwitch: UISwitch!
    @IBOutlet weak var debugLoggingHostnameTextField: UITextField!
    @IBOutlet weak var debugLoggingPortTextField: UITextField!

    @IBOutlet weak var only2HoursSwitcher: UISwitch!
    @IBOutlet weak var uuidLabel: UILabel!
    @IBOutlet weak var testCounterLabel: UILabel!
    @IBOutlet weak var buildDetailsLabel: UILabel!
    @IBOutlet weak var developerNameLabel: UILabel!

    @IBOutlet weak var websiteURLLabel: UILabel!
    @IBOutlet weak var emailAddressLabel: UILabel!

    weak var delegate: RMBTSettingsViewControllerDelegate?

    private let settings = RMBTSettings.shared
    
    private var uuid: String?
    
    private var generalSettings: [IndexPath] = []
    private var advancedSettings: [IndexPath] = []
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        prepareGeneralSettings()
        prepareAdvancedSettings()
        
        self.title = NSLocalizedString("preferences_general_settings", comment: "")
        self.navigationItem.leftBarButtonItem = self.closeBarButtonItem
        
        self.developerNameLabel.text = RMBTConfig.RMBT_DEVELOPER_NAME
        self.buildDetailsLabel.lineBreakMode = NSLineBreakMode.byCharWrapping
        
        let shortVersion = RMBTHelpers.version
        let version = RMBTHelpers.buildNumber
        
        self.buildDetailsLabel.text = String(format:"%@(%@) %@\n(%@)",
                                             shortVersion,
                                             version,
                                             RMBTHelpers.RMBTBuildInfoString(),
                                             RMBTHelpers.RMBTBuildDateString())

        self.uuidLabel.lineBreakMode = NSLineBreakMode.byCharWrapping;
        self.uuidLabel.numberOfLines = 0

        self.websiteURLLabel.text = RMBTConfig.RMBT_PROJECT_URL
        self.emailAddressLabel.text = RMBTConfig.RMBT_PROJECT_EMAIL
        
        self.updateLocationState(self)
        
        NotificationCenter.default.addObserver(self, selector: #selector(updateLocationState(_:)), name: UIApplication.didBecomeActiveNotification, object: nil)
        
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(tapHandler(_:)))
        tapGestureRecognizer.numberOfTapsRequired = 10
        self.buildDetailsLabel.addGestureRecognizer(tapGestureRecognizer)

        self.bindSwitch(self.forceIPv4Switch, to: #keyPath(RMBTSettings.forceIPv4), onToggle: { value in
            if (value && self.settings.debugUnlocked && self.debugForceIPv6Switch.isOn) {
                self.settings.debugForceIPv6 = false
                self.debugForceIPv6Switch.setOn(false, animated: true)
            }
        })
        
        self.bindSwitch(self.skipQoSSwitch, to: #keyPath(RMBTSettings.qosEnabled), onToggle: { value in
            if (value == false) {
                self.settings.only2Hours = false
                self.only2HoursSwitcher.setOn(false, animated: true)
            } else {
                self.settings.only2Hours = true
                self.only2HoursSwitcher.setOn(true, animated: true)
            }
            self.prepareGeneralSettings()
            self.refreshSection(.general)
        })
        
        self.bindSwitch(self.only2HoursSwitcher, to: #keyPath(RMBTSettings.only2Hours)) { value in
            //Remove previousLaunchQoSDate. We can't set nil, because we will have crash
            self.settings.previousLaunchQoSDate = Date(timeIntervalSince1970: 0)
        }
        
        self.bindSwitch(self.expertModeSwitch, to: #keyPath(RMBTSettings.expertMode)) { value in
            if (value == false) {
                self.settings.forceIPv4 = false
                self.forceIPv4Switch.setOn(false, animated: false)
            }
            self.prepareAdvancedSettings()
            self.tableView.reloadData()
        }
        
        self.bindSwitch(self.loopModeSwitch, to: #keyPath(RMBTSettings.loopMode)) { value in
            if (value) {
                // forget value in case user terminates the app while in the modal dialog
                self.settings.loopMode = false
                self.prepareAdvancedSettings()
                self.performSegue(withIdentifier: "show_loop_mode_confirmation", sender:self)
            } else {
                self.prepareAdvancedSettings()
                self.refreshSection(.advanced)
            }
        }

        rebindLoopModeSettings()
        
        self.bindSwitch(self.debugForceIPv6Switch, to: #keyPath(RMBTSettings.debugForceIPv6)) { value in
            if (value && self.forceIPv4Switch.isOn) {
                self.settings.forceIPv4 = false
                self.forceIPv4Switch.setOn(false, animated: true)
            }
        }

        self.bindSwitch(self.debugControlServerCustomizationEnabledSwitch,
                        to: #keyPath(RMBTSettings.debugControlServerCustomizationEnabled)) { value in
            self.refreshSection(.debugCustomControlServer)
        }

        self.bindTextField(self.debugControlServerHostnameTextField,
                           to: #keyPath(RMBTSettings.debugControlServerHostname), isNumeric: false)
        
        self.bindTextField(self.debugControlServerPortTextField, to: #keyPath(RMBTSettings.debugControlServerPort), isNumeric: true)

        self.bindSwitch(self.debugControlServerUseSSLSwitch,
                        to: #keyPath(RMBTSettings.debugControlServerUseSSL), onToggle: nil)

        self.bindSwitch(self.debugLoggingEnabledSwitch,
                        to: #keyPath(RMBTSettings.debugLoggingEnabled)) { value in
            self.refreshSection(.logging)
            self.updateLogging()
        }

        self.bindTextField(self.debugLoggingHostnameTextField, to: #keyPath(RMBTSettings.debugLoggingHostname), isNumeric: false) { value in
            self.updateLogging()
        }

        self.bindTextField(self.debugLoggingPortTextField, to: #keyPath(RMBTSettings.debugLoggingPort), isNumeric: true) { value in
            self.updateLogging()
        }
    }
    
    private func rebindLoopModeSettings() {
        self.bindTextField(self.loopModeWaitTextField,
                           to: #keyPath(RMBTSettings.loopModeEveryMinutes),
                           isNumeric: true,
                           min: Int(settings.debugUnlocked ? 0 : RMBTConfig.RMBT_TEST_LOOPMODE_MIN_DELAY_MINS),
                           max: Int(settings.debugUnlocked ? Int.max : RMBTConfig.RMBT_TEST_LOOPMODE_MAX_DELAY_MINS))
        
        
        self.bindTextField(self.loopModeDistanceTextField,
                           to: #keyPath(RMBTSettings.loopModeEveryMeters),
                           isNumeric: true,
                           min: Int(settings.debugUnlocked ? 0 : RMBTConfig.RMBT_TEST_LOOPMODE_MIN_MOVEMENT_M),
                           max: Int(settings.debugUnlocked ? Int.max : RMBTConfig.RMBT_TEST_LOOPMODE_MAX_MOVEMENT_M))
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Refresh test counter and uuid labels:
        self.testCounterLabel.text = String(format: "%lu", settings.testCounter)
        uuid = RMBTControlServer.shared.uuid
        if let uuid = RMBTControlServer.shared.uuid {
            self.uuidLabel.text = "U\(uuid)"
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        self.delegate?.settingsDidChanged(in: self)
        
        RMBTControlServer.shared.updateWithCurrentSettings {
        } error: { error in
        }
        
        super.viewWillDisappear(animated)
    }
    
    func prepareGeneralSettings() {
        self.generalSettings = []
        self.generalSettings.append(IndexPath(row: 0, section: RMBTSettingsSection.general.rawValue))
        
        if settings.qosEnabled {
            self.generalSettings.append(IndexPath(row: 1, section: RMBTSettingsSection.general.rawValue))
        }
        if !RMBTLocationTracker.shared.isAuthorized {
            self.generalSettings.append(IndexPath(row: 2, section: RMBTSettingsSection.general.rawValue))
        }
    }
   
    func prepareAdvancedSettings() {
        self.advancedSettings = []
        
        self.advancedSettings.append(IndexPath(row: 0, section: RMBTSettingsSection.advanced.rawValue))
        
        if settings.loopMode {
            self.advancedSettings.append(IndexPath(row: 1, section: RMBTSettingsSection.advanced.rawValue))
            self.advancedSettings.append(IndexPath(row: 2, section: RMBTSettingsSection.advanced.rawValue))
        }
        
        self.advancedSettings.append(IndexPath(row: 3, section: RMBTSettingsSection.advanced.rawValue))
        
        if settings.expertMode {
            self.advancedSettings.append(IndexPath(row: 4, section: RMBTSettingsSection.advanced.rawValue))
        }
    }
    
    func refreshSection(_ section: RMBTSettingsSection) {
        let indexSet = IndexSet(integer: section.rawValue)
        self.tableView.beginUpdates()
        self.tableView.reloadSections(indexSet, with: .automatic)
        self.tableView.reloadData()
        self.tableView.endUpdates()
    }
    
    // MARK: - Two-way binding helpers
    
    func bindSwitch(_ aSwitch: UISwitch, to settingsKeyPath: String, onToggle: ((_ value: Bool) -> Void)?) {
        aSwitch.isOn = (settings.value(forKey: settingsKeyPath) as? Bool) ?? false
        aSwitch.bk_addEventHandler({ sender in
            guard let sender = sender as? UISwitch else { return }
            self.settings.setValue(sender.isOn, forKey: settingsKeyPath)
            onToggle?(sender.isOn)
        }, for: .valueChanged)
    }
    
    func bindTextField(_ aTextField: UITextField, to settingsKeyPath: String, isNumeric: Bool, onChanged: ((_ value: String?) -> Void)? = nil) {
        self.bindTextField(aTextField, to: settingsKeyPath, isNumeric: isNumeric, min: Int.min, max: Int.max, onChanged: onChanged)
    }

    func bindTextField(_ aTextField: UITextField, to settingsKeyPath: String, isNumeric: Bool, min: Int, max: Int, onChanged: ((_ value: String?) -> Void)? = nil) {
        var stringValue = ""
        
        let block: (_ textField: Any) -> Void = { textField in
            guard let textField = textField as? UITextField else { return }
            var value = Int(textField.text ?? "") ?? 0
            if (isNumeric && (value < min)) {
                textField.text = String(min)
                value = min
            } else if (isNumeric && value > max) {
                textField.text = String(max)
                value = max
            } else if isNumeric {
                textField.text = String(value)
            }
            
            let newValue: AnyObject?
            
            if isNumeric {
                newValue = value as AnyObject?
            } else {
                newValue = textField.text as AnyObject?
            }
            self.settings.setValue(newValue, forKey: settingsKeyPath)
            onChanged?(newValue as? String)
        }
        
        if let val = settings.value(forKey: settingsKeyPath) {
            if isNumeric {
                stringValue = (val as? NSNumber)?.stringValue ?? ""
            } else {
                stringValue = val as? String ?? ""
            }
        }
        
        if isNumeric && stringValue == "0" && min != 0 {
            stringValue = ""
        }
        
        aTextField.text = stringValue

        aTextField.bk_removeEventHandlers(for: .editingDidEnd)
        aTextField.bk_addEventHandler(block, for: .editingDidEnd)
        block(aTextField)
    }
    
    @objc func updateLocationState(_ sender: Any) {
        self.prepareGeneralSettings()
        self.tableView.reloadData()
    }
    
    @IBAction func declineLoopModeConfirmation(_ segue: UIStoryboardSegue) {
        self.loopModeSwitch.setOn(false, animated: true)
        segue.source.dismiss(animated: true, completion: nil)
    }
    
    @IBAction func acceptLoopModeConfirmation(_ segue: UIStoryboardSegue) {
        settings.loopMode = true
        self.prepareAdvancedSettings()
        self.refreshSection(.advanced)
    }
    
    func searchTextField(in view: UIView) -> UITextField? {
        if let textField = view as? UITextField {
            return textField
        }
        else {
            for v in view.subviews {
                if let textField = searchTextField(in: v) {
                    return textField
                }
            }
        }
        
        return nil
    }
    
    // MARK: - Table View
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        let lastSectionIndex = settings.debugUnlocked ? RMBTSettingsSection.logging : RMBTSettingsSection.support
        return lastSectionIndex.rawValue + 1
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if (indexPath.section == RMBTSettingsSection.general.rawValue) {
            let itemIndexPath = self.generalSettings[indexPath.row]
            return super.tableView(tableView, cellForRowAt: itemIndexPath)
        } else if (indexPath.section == RMBTSettingsSection.advanced.rawValue) {
            let itemIndexPath = self.advancedSettings[indexPath.row]
            return super.tableView(tableView, cellForRowAt: itemIndexPath)
        } else {
            return super.tableView(tableView, cellForRowAt: indexPath)
        }
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if (section == RMBTSettingsSection.general.rawValue) {
            return self.generalSettings.count
        }
        if (section == RMBTSettingsSection.advanced.rawValue) {
            return self.advancedSettings.count
        } else if (section == RMBTSettingsSection.advanced.rawValue && !settings.loopMode) {
            return 1 // hide customization
        } else if (section == RMBTSettingsSection.debugCustomControlServer.rawValue && !settings.debugControlServerCustomizationEnabled) {
            return 1 // hide customization
        } else if (section == RMBTSettingsSection.logging.rawValue && !settings.debugLoggingEnabled) {
            return 1 // hide customization
        } else {
            return super.tableView(tableView, numberOfRowsInSection: section)
        }
    }
    
    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let title = self.tableView(tableView, titleForHeaderInSection: section)
        let height = self.tableView(tableView, heightForHeaderInSection: section)
        let view = UIView(frame: CGRect(x: 0, y: 0, width: tableView.bounds.size.width, height: height))
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.backgroundColor = UIColor.clear
        
        let label = RMBTTitleSectionLabel(text: title)
        label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        label.frame = CGRect(x: 20, y: 0, width: view.bounds.size.width - 40, height: height)
        view.addSubview(label)
        
        return view
    }

    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return 48
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let sectionEnum = RMBTSettingsSection(rawValue: section) else {
            return super.tableView(tableView, titleForHeaderInSection: section)
        }
        
        switch (sectionEnum) {
        case .general:
            return NSLocalizedString("preferences_general_settings", comment: "")
        case .advanced:
                return NSLocalizedString("preferences_advanced_settings", comment: "")
        case .contacts:
                return NSLocalizedString("preferences_contact", comment: "")
        case .info:
                return NSLocalizedString("preferences_additional_Information", comment: "")
        case .support:
                return NSLocalizedString("preferences_about", comment: "")
        case .debug:
                return NSLocalizedString("preferences_debug_options", comment: "")
        case .debugCustomControlServer:
                return NSLocalizedString("preferences_developer_control_server", comment: "")
        case .logging:
                return NSLocalizedString("preferences_developer_logging", comment: "")
        }
    }
    
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if (section == RMBTSettingsSection.logging.rawValue) {
            return NSLocalizedString("preferences_developer_logging_summary", comment: "")
        }
        return super.tableView(tableView, titleForFooterInSection: section)
        
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if (indexPath.section == RMBTSettingsSection.general.rawValue) {
            var index = 1
            if (settings.qosEnabled) {
                index += 1
            }
            switch (indexPath.row) {
                case index:
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url, options: [:], completionHandler: nil)
                }
                default: break
            }
        } else if (indexPath.section == RMBTSettingsSection.contacts.rawValue) {
            switch (indexPath.row) {
            case 0: self.openURL(URL(string: RMBTConfig.RMBT_PROJECT_URL))
                case 1:
                if MFMailComposeViewController.canSendMail() {
                    let mailVC = MFMailComposeViewController()
                    mailVC.setToRecipients([RMBTConfig.RMBT_PROJECT_EMAIL])
                    mailVC.mailComposeDelegate = self
                    self.present(mailVC, animated: true, completion: nil)
                }
                case 2:
                if let tosUrl = RMBTControlServer.shared.termsAndConditions.url,
                    let url = URL(string: tosUrl) {
                    self.openURL(url)
                }
                default: assert(false, "Invalid row")
            }
        } else if (indexPath.section == RMBTSettingsSection.support.rawValue) {
            switch (indexPath.row) {
            case 0: self.openURL(URL(string: RMBTConfig.RMBT_REPO_URL))
            case 1: self.openURL(URL(string: RMBTConfig.RMBT_DEVELOPER_URL))
            case 2: if let tosUrl = RMBTControlServer.shared.termsAndConditions.url,
                       let url = URL(string: tosUrl) {
                       self.openURL(url)
                   }
            default: break
            }
        }
        
        if let cell = tableView.cellForRow(at: indexPath),
           let textField = self.searchTextField(in: cell) {
            if !textField.isFirstResponder {
                textField.becomeFirstResponder()
            }
        }

        tableView.deselectRow(at: indexPath, animated: true)
    }
    
    // MARK: - Tableview actions (copying UUID)

    // Show "Copy" action for cell showing client UUID
    override func tableView(_ tableView: UITableView, shouldShowMenuForRowAt indexPath: IndexPath) -> Bool {
        if (indexPath.section == RMBTSettingsSection.info.rawValue && indexPath.row == 0 && uuid != nil) {
            return true
        } else {
            return false
        }
    }
    
    // As client UUID is the only cell we can perform action for, we allow "copy" here
    override func tableView(_ tableView: UITableView, canPerformAction action: Selector, forRowAt indexPath: IndexPath, withSender sender: Any?) -> Bool {
        return action == #selector(copy(_:))
    }

    // ..and we copy the UUID value to pastboard in case "copy" action is performed
    override func tableView(_ tableView: UITableView, performAction action: Selector, forRowAt indexPath: IndexPath, withSender sender: Any?) {
        if action == #selector(copy(_:)) {
            // Copy UUID to pasteboard
            UIPasteboard.general.string = uuid
        }
    }
}

extension RMBTSettingsViewController {
    @objc func tapHandler(_ sender: UIGestureRecognizer) {
        _ = UIAlertController.presentAlertDevCode(nil, codeAction: { [weak self] (textField) in
            guard let self = self else { return }
            
            guard textField.text == RMBTConfig.ACTIVATE_DEV_CODE || textField.text == RMBTConfig.DEACTIVATE_DEV_CODE else { return }
            
            let isEnable = textField.text == RMBTConfig.ACTIVATE_DEV_CODE
            self.settings.isDevModeEnabled = isEnable
            self.settings.debugUnlocked = isEnable
            if !isEnable {
                self.settings.debugForceIPv6 = false
            }
            self.rebindLoopModeSettings()
            self.tableView.reloadData()
        }, textFieldConfiguration: nil)
    }
    
    @objc var closeBarButtonItem: UIBarButtonItem {
        let closeBarButtonItem = UIBarButtonItem(image: .closeImage, style: .done, target: self, action: #selector(closeButtonClick(_:)))
        return closeBarButtonItem
    }
    
    @objc func closeButtonClick(_ sender: Any) {
        self.dismiss(animated: true)
    }
    
    @objc func updateLogging() {
        LogConfig.enableLogging = settings.debugLoggingEnabled
    }
}

extension RMBTSettingsViewController: UITextFieldDelegate {
    func textFieldDidBeginEditing(_ textField: UITextField) {
        DispatchQueue.main.async {
            textField.goToEndPosition()
        }
    }
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}

extension RMBTSettingsViewController: MFMailComposeViewControllerDelegate {
    func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
        self.dismiss(animated: true, completion: nil)
    }
}

private extension UIImage {
    static let closeImage = UIImage(named: "black_close_button")
}
