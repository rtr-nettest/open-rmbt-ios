//
//  KeepScreenAwakeModifier.swift
//  RMBT
//
//  Copyright © 2026 appscape gmbh. All rights reserved.
//

import SwiftUI
import UIKit

private struct KeepScreenAwakeModifier: ViewModifier {
    let isActive: Bool

    func body(content: Content) -> some View {
        content
            .onAppear { apply(isActive) }
            .onChange(of: isActive) { newValue in
                apply(newValue)
            }
            .onDisappear { apply(false) }
    }

    private func apply(_ disabled: Bool) {
        UIApplication.shared.isIdleTimerDisabled = disabled
    }
}

extension View {
    /// Prevents iOS from dimming and auto-locking the screen while `isActive` is true.
    /// The flag is always cleared on disappear so leaving the screen restores normal auto-lock,
    /// even if `isActive` was true at the time.
    func keepScreenAwake(while isActive: Bool) -> some View {
        modifier(KeepScreenAwakeModifier(isActive: isActive))
    }
}
