//
//  RMBTHistorySyncModalViewController.swift
//  RMBT
//
//  Created by Polina on 03.11.2021.
//  Copyright © 2021 appscape gmbh. All rights reserved.
//

import UIKit

// MARK: Init

class RMBTHistorySyncModalViewController: UIViewController {
    
    @IBOutlet weak var dialogView: UIView!
    @IBOutlet weak var dialogHeightContraint: NSLayoutConstraint!
    @IBOutlet weak var dialogTitle: UILabel!
    @IBOutlet weak var dialogDescription: UITextView!
    @IBOutlet weak var defaultButtonsView: UIStackView!
    @IBOutlet weak var requestCodeButton: UIButton!
    @IBOutlet weak var enterCodeButton: UIButton!
    @IBOutlet weak var enterCodeView: UIStackView!
    @IBOutlet weak var syncCodeTextField: RMBTMaterialTextField!
    @IBOutlet weak var enterCodeConfirmButton: UIButton!
    @IBOutlet weak var enterCodeConfirmButtonLandscape: UIButton!
    @IBOutlet weak var requestCodeView: UIStackView!
    @IBOutlet weak var syncCode: UILabel!
    @IBOutlet weak var closeButton: UIButton!
    @IBOutlet var backgroundView: UIView!
    @IBOutlet weak var spinnerView: UIView!
    @IBOutlet weak var syncResultView: UIStackView!
    @IBOutlet weak var syncResultCloseButton: UIButton!
    @IBOutlet weak var dialogYConstraint: NSLayoutConstraint!
    @IBOutlet weak var syncImageView: UIImageView!
    lazy var enterCodeViewBottomConstraint: NSLayoutConstraint = {
        return NSLayoutConstraint(item: self.enterCodeView!, attribute: .bottom, relatedBy: .equal, toItem: self.dialogView, attribute: .bottom, multiplier: 1.0, constant: -16)
    }()
    lazy var enterCodeViewTopConstraint: NSLayoutConstraint = {
        return NSLayoutConstraint(item: self.enterCodeView!, attribute: .centerY, relatedBy: .equal, toItem: self.dialogView, attribute: .centerY, multiplier: 1.0, constant: 24)
    }()
    
    private var state: RMBTHistorySyncModalState?
    private var isLandscape: Bool {
        return view.frame.width > view.frame.height
    }
    var onSyncSuccess: (() -> Void)?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        backgroundView.backgroundColor = .black.withAlphaComponent(0.0)
        syncCodeTextField.placeholderLabel.isHidden = isPlaceholderOverlappingWithDescription(height: view.frame.height)
        NSLayoutConstraint.activate([enterCodeViewBottomConstraint])
        setState(RMBTHistorySyncModalState())
        setActionHandlers()
        setTexts()
        NotificationCenter.default.addObserver(self, selector: #selector(moveDialogOnTopOfKeyboard), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        view.endEditing(true)
        syncCodeTextField.setState(RMBTMaterialTextFieldState(frame: syncCodeTextField.frame))
        syncCodeTextField.placeholderLabel.isHidden = isPlaceholderOverlappingWithDescription(height: size.height)
    }
    
    private func setState(_ state: RMBTHistorySyncModalState) {
        self.state = state
        dialogTitle.text = state.dialogTitle
        dialogDescription.text = state.dialogDescription
        requestCodeView.isHidden = state.isRequestCodeViewHidden
        syncCode.text = state.syncCode
        enterCodeView.isHidden = state.isEnterCodeViewHidden
        defaultButtonsView.isHidden = state.isDefaultButtonsViewHidden
        spinnerView.isHidden = state.isSpinnerViewHidden
        syncResultView.isHidden = state.isSyncResultViewHidden
        if !state.isEnterCodeViewHidden {
            syncCodeTextField.becomeFirstResponder()
        }
        syncCodeTextField.errorText = state.syncError
        UIView.animate(withDuration: 0.1) {
            self.dialogHeightContraint.constant = state.dialogHeight
        }
    }
    
    private func setTexts() {
        closeButton.setTitle(.closeButton, for: .normal)
        enterCodeButton.setTitle(.enterCodeButton, for: .normal)
        enterCodeConfirmButton.setTitle(.enterCodeButton, for: .normal)
        enterCodeConfirmButtonLandscape.setTitle(.enterCodeButton, for: .normal)
        requestCodeButton.setTitle(.requestCodeButton, for: .normal)
        syncCodeTextField.placeholder = .code
        syncResultCloseButton.setTitle(.closeButton, for: .normal)
    }
    
    private func isPlaceholderOverlappingWithDescription(height: CGFloat) -> Bool {
        return height < 667.0
    }
}

// MARK: Action handlers

extension RMBTHistorySyncModalViewController {
    private func setActionHandlers() {
        backgroundView.addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(closeDialog))
        )
        dialogView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleDialogTap)))
        closeButton.addTarget(self, action: #selector(closeDialog), for: .touchUpInside)
        enterCodeButton.addTarget(self, action: #selector(showEnterCodeView), for: .touchUpInside)
        enterCodeConfirmButton.addTarget(self, action: #selector(syncWithCode), for: .touchUpInside)
        enterCodeConfirmButtonLandscape.addTarget(self, action: #selector(syncWithCode), for: .touchUpInside)
        requestCodeButton.addTarget(self, action: #selector(showRequestCodeView), for: .touchUpInside)
        syncResultCloseButton.addTarget(self, action: #selector(closeDialog), for: .touchUpInside)
    }

    @objc func closeDialog() {
        if state is RMBTHistorySyncModalStateRequestCode {
            self.onSyncSuccess?()
        }
        self.dismiss(animated: true)
    }
    
    @objc func showEnterCodeView() {
        setState(RMBTHistorySyncModalStateEnterCode())
    }
    
    @objc func showRequestCodeView() {
        if let state = state {
            setState(state.copyWith(isSpinnerViewHidden: false))
        }
        RMBTControlServer.shared.getSyncCode(success: { response in
            guard let code = response.codes?.first?.code else {
                return self.setState(RMBTHistorySyncModalState())
            }
            self.setState(RMBTHistorySyncModalStateRequestCode(code))
        }, error: { error in
            Log.logger.error(error)
            self.setState(RMBTHistorySyncModalState())
        })
    }
    
    @objc func syncWithCode() {
        guard let code = syncCodeTextField.text?.uppercased(), code.count == 12 else {
            return setState(RMBTHistorySyncModalStateSyncError(.codeLengthError))
        }
        if let state = state {
            setState(state.copyWith(isSpinnerViewHidden: false))
        }
        RMBTControlServer.shared.syncWithCode(code, success: { response in
            if response.sync.count > 0, response.sync[0].success == false {
                let errorMsg = NSLocalizedString(response.sync[0].messageText ?? "", comment: "")
                self.setState(RMBTHistorySyncModalStateSyncError(errorMsg))
                return
            }
            self.setState(RMBTHistorySyncModalStateSyncSuccess())
            self.onSyncSuccess?()
        }, error: { error in
            let errorMsg = (error as NSError?)?.userInfo["msg_text"] as? String
            self.setState(RMBTHistorySyncModalStateSyncError(errorMsg))
        })

    }
    
    @objc func handleDialogTap() {
        syncCodeTextField.resignFirstResponder()
    }
    
    @objc func moveDialogOnTopOfKeyboard(notification: NSNotification) {
        guard let info = notification.userInfo, let keyboardFrame = info[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue else { return }
        let isCodeViewHiddenByKeyboard = keyboardFrame.cgRectValue.origin.y < UIScreen.main.bounds.size.height
        
        UIView.animate(withDuration: 0.1) {
            self.dialogYConstraint.constant = isCodeViewHiddenByKeyboard ? -(keyboardFrame.cgRectValue.size.height / 2 - (self.isLandscape ? 0 : 20)) : 0.0
            if self.isLandscape && isCodeViewHiddenByKeyboard {
                self.syncImageView.layer.opacity = 0.0
                self.dialogTitle.layer.opacity = 0.0
                self.dialogDescription.layer.opacity = 0.0
                NSLayoutConstraint.deactivate([ self.enterCodeViewBottomConstraint ])
                NSLayoutConstraint.activate([ self.enterCodeViewTopConstraint ])
                if self.enterCodeConfirmButtonLandscape.isHidden {
                    self.enterCodeConfirmButtonLandscape.isHidden = false
                }
                self.enterCodeConfirmButton.layer.opacity = 0.0
                self.syncCodeTextField.placeholderLabel.isHidden = false
                self.syncCodeTextField.placeholderLabel.textAlignment = .left
                self.syncCodeTextField.errorLabel.textAlignment = .left
                self.syncCodeTextField.textAlignment = .left
            } else {
                self.syncImageView.layer.opacity = 1.0
                self.dialogTitle.layer.opacity = 1.0
                self.dialogDescription.layer.opacity = isCodeViewHiddenByKeyboard && self.isPlaceholderOverlappingWithDescription(height: self.view.frame.height) ? 0.0 : 1.0
                NSLayoutConstraint.activate([ self.enterCodeViewBottomConstraint ])
                NSLayoutConstraint.deactivate([ self.enterCodeViewTopConstraint ])
                if !self.enterCodeConfirmButtonLandscape.isHidden {
                    self.enterCodeConfirmButtonLandscape.isHidden = true
                }
                self.enterCodeConfirmButton.layer.opacity = 1.0
                self.syncCodeTextField.placeholderLabel.textAlignment = .center
                self.syncCodeTextField.errorLabel.textAlignment = .center
                self.syncCodeTextField.textAlignment = .center
            }
            self.view.layoutIfNeeded()
        }
    }
}

// MARK: Localizations

private extension String {
    static let enterCodeButton = NSLocalizedString("Enter code", comment: "").uppercased()
    static let requestCodeButton = NSLocalizedString("Request code", comment: "").uppercased()
    static let closeButton = NSLocalizedString("Close", comment: "").uppercased()
    static let code = NSLocalizedString("Code", comment: "")
    static let codeLengthError = NSLocalizedString("The code must consist of twelve characters", comment: "")
}
