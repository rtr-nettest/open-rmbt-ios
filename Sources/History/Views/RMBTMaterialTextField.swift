//
//  RMBTMaterialTextField.swift
//  RMBT
//
//  Created by Polina on 08.11.2021.
//  Copyright © 2021 appscape gmbh. All rights reserved.
//

import UIKit

// MARK: Init

class RMBTMaterialTextField: UITextField {

    var bottomBorder: CALayer!
    var placeholderLabel: UILabel!
    var placeholderText: String?
    var errorLabel: UILabel!

    var errorText: String? {
        didSet {
            errorLabel.text = errorText
            if errorText != nil {
                UIView.animate(withDuration: 0.2) {
                    self.setState(RMBTMaterialTextFieldStateError(frame: self.frame))
                }
            } else {
                UIView.animate(withDuration: 0.1) {
                    self.setState(RMBTMaterialTextFieldStateFocus(frame: self.frame))
                }
            }
        }
    }

    var floatingLabelFont: UIFont = UIFont.roboto(size: 13, weight: .regular)

    override init(frame: CGRect) {
        super.init(frame: frame)
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setPlaceholderLabel()
        setErrorLabel()
        setBorder()
        setState(RMBTMaterialTextFieldState(frame: frame))
        setActionHandlers()
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        bottomBorder.frame = CGRect(x: 0.0, y: frame.height - 2, width: frame.width, height: 2.0)
        layer.addSublayer(bottomBorder)
    }
    
    func setState(_ state: RMBTMaterialTextFieldState) {
        bottomBorder.backgroundColor = state.placeholderColor.cgColor
        errorLabel.textColor = state.placeholderColor
        placeholderLabel.textColor = state.placeholderColor
        tintColor = state.placeholderColor
        errorLabel.frame = state.errorLabelFrame
        placeholderLabel.frame = state.placeholderLabelFrame
    }
    
    private func setBorder() {
        borderStyle = .none
        bottomBorder = CALayer()
    }
    
    private func setErrorLabel() {
        let flotingLabelFrame = CGRect(x: 0, y: 0, width: frame.width, height: 0)
        errorLabel = UILabel(frame: flotingLabelFrame)
        errorLabel.font = floatingLabelFont
        errorLabel.numberOfLines = 0
        errorLabel.textAlignment = .center
        addSubview(errorLabel)
    }
    
    private func setPlaceholderLabel() {
        let flotingLabelFrame = CGRect(x: 0, y: 0, width: frame.width, height: 0)
        placeholderLabel = UILabel(frame: flotingLabelFrame)
        placeholderLabel.font = floatingLabelFont
        placeholderLabel.text = placeholder
        placeholderLabel.textAlignment = .center
        placeholderText = placeholder
        addSubview(placeholderLabel)
    }
}

// MARK: Action handlers

extension RMBTMaterialTextField {
    private func setActionHandlers() {
        addTarget(self, action: #selector(textFieldDidBeginEditing), for: .editingDidBegin)
        addTarget(self, action: #selector(textFieldDidEndEditing), for: .editingDidEnd)
        addTarget(self, action: #selector(textFieldDidChange), for: .editingChanged)
    }

    @objc func textFieldDidBeginEditing() {

        if text == "" {
            UIView.animate(withDuration: 0.2) {
                self.setState(RMBTMaterialTextFieldStateFocus(frame: self.frame))
            }
            placeholder = ""
        } else if errorText != nil {
            errorText = nil
        }
    }
    
    @objc func textFieldDidChange() {
        if errorText != nil {
            errorText = nil
        }
    }

    @objc func textFieldDidEndEditing() {

        if text == "" {
            UIView.animate(withDuration: 0.1) {
                self.setState(RMBTMaterialTextFieldState(frame: self.frame))
            }
            placeholder = placeholderText
        }
    }
}
