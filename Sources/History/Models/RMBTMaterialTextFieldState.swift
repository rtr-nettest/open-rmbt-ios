//
//  RMBTMaterialTextFieldState.swift
//  RMBT
//
//  Created by Polina on 08.11.2021.
//  Copyright © 2021 appscape gmbh. All rights reserved.
//

import UIKit

// MARK: Default state

class RMBTMaterialTextFieldState {
    var floatingLabelHeight: CGFloat = 24
    var frame: CGRect!

    var placeholderColor: UIColor {
        return .defaultColor
    }
    var errorLabelFrame: CGRect {
        return CGRect(x: 0, y: frame.height + 2, width: frame.width, height: 0)
    }
    var placeholderLabelFrame: CGRect {
        return CGRect(x: 0, y: 0, width: frame.width, height: 0)
    }
    
    init(frame: CGRect) {
        self.frame = frame
    }
}

// MARK: Focus state

class RMBTMaterialTextFieldStateFocus: RMBTMaterialTextFieldState {
    override var placeholderColor: UIColor {
        return .focusColor ?? super.placeholderColor
    }
    
    override var placeholderLabelFrame: CGRect {
        return CGRect(x: 0, y: -floatingLabelHeight, width: frame.width, height: floatingLabelHeight)
    }
}

// MARK: Error state

class RMBTMaterialTextFieldStateError: RMBTMaterialTextFieldState {
    override var placeholderColor: UIColor {
        return .errorColor
    }
    
    override var placeholderLabelFrame: CGRect {
        return CGRect(x: 0, y: -floatingLabelHeight, width: frame.width, height: floatingLabelHeight)
    }
    
    override var errorLabelFrame: CGRect {
        return CGRect(x: 0, y: frame.height + 2, width: frame.width, height: floatingLabelHeight * 1.5)
    }
}

// MARK: Colors

private extension UIColor {
    static let defaultColor = UIColor(red: 0.75, green: 0.75, blue: 0.79, alpha: 1)
    static let focusColor = UIColor(named: "greenButtonBackground")
    static let errorColor = UIColor.red
}
