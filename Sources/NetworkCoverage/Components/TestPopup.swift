//
//  TestStartPopup.swift
//  RMBT
//
//  Created by Jiri Urbasek on 25.06.2025.
//  Copyright 2025 appscape gmbh. All rights reserved.
//

import SwiftUI

struct TestPopup: View {
    let title: String
    let subtitle: String
    let primaryButtonTitle: String
    let primaryButtonColor: Color
    let secondaryButtonTitle: String
    let onPrimaryAction: () -> Void
    let onSecondaryAction: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            VStack(spacing: 16) {
                Text(title)
                    .font(.title2)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)

                Text(subtitle)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 16) {
                // Primary action button
                Button(action: onPrimaryAction) {
                    Text(primaryButtonTitle)
                        .font(.callout)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .frame(height: 50)
                        .frame(maxWidth: .infinity)
                        .background(primaryButtonColor)
                        .cornerRadius(8)
                }

                // Secondary action button
                Button(action: onSecondaryAction) {
                    Text(secondaryButtonTitle)
                        .font(.callout)
                        .fontWeight(.medium)
                        .frame(height: 50)
                        .frame(maxWidth: .infinity)
                }
                .tint(.brand)
            }
        }
        .padding(.top, 8)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
        )
        .padding(.horizontal, 16)
    }
}

// MARK: - Generic Test Popup Modifier
struct TestPopupModifier: ViewModifier {
    @Binding var isPresented: Bool
    let title: String
    let subtitle: String
    let primaryButtonTitle: String
    let primaryButtonColor: Color
    let secondaryButtonTitle: String
    let onPrimaryAction: () -> Void
    let onSecondaryAction: () -> Void
    let allowBackgroundDismiss: Bool

    func body(content: Content) -> some View {
        content
            .overlay(
                // Background overlay
                Group {
                    if isPresented {
                        Rectangle()
                            .fill(Color.black.opacity(0.4))
                            .ignoresSafeArea()
                            .onTapGesture {
                                if allowBackgroundDismiss {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        isPresented = false
                                    }
                                }
                            }
                            .transition(.opacity)
                    }
                }
            )
            .overlay(
                // Popup content - centered in screen
                Group {
                    if isPresented {
                        TestPopup(
                            title: title,
                            subtitle: subtitle,
                            primaryButtonTitle: primaryButtonTitle,
                            primaryButtonColor: primaryButtonColor,
                            secondaryButtonTitle: secondaryButtonTitle,
                            onPrimaryAction: {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    isPresented = false
                                }
                                onPrimaryAction()
                            },
                            onSecondaryAction: {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    isPresented = false
                                }
                                onSecondaryAction()
                            }
                        )
                        .padding(.horizontal, 20)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea(.keyboard, edges: .bottom)
            )
            .animation(.easeInOut(duration: 0.3), value: isPresented)
    }
}

// MARK: - View Extensions
extension View {
    func testStartPopup(
        isPresented: Binding<Bool>,
        title: String,
        subtitle: String,
        onStartTest: @escaping () -> Void,
        onCancel: @escaping () -> Void = {}
    ) -> some View {
        modifier(
            TestPopupModifier(
                isPresented: isPresented,
                title: title,
                subtitle: subtitle,
                primaryButtonTitle: "Start test",
                primaryButtonColor: Color("greenButtonBackground"),
                secondaryButtonTitle: NSLocalizedString("Cancel", comment: ""),
                onPrimaryAction: onStartTest,
                onSecondaryAction: onCancel,
                allowBackgroundDismiss: false
            )
        )
    }
    
    func testStopPopup(
        isPresented: Binding<Bool>,
        title: String,
        subtitle: String,
        onStopTest: @escaping () -> Void
    ) -> some View {
        modifier(
            TestPopupModifier(
                isPresented: isPresented,
                title: title,
                subtitle: subtitle,
                primaryButtonTitle: "Continue test",
                primaryButtonColor: Color("greenButtonBackground"),
                secondaryButtonTitle: "Stop test",
                onPrimaryAction: {}, // Continue just dismisses
                onSecondaryAction: onStopTest,
                allowBackgroundDismiss: false
            )
        )
    }
}

#Preview {
    ZStack {
        Color.gray.opacity(0.2)
        TestPopup(
            title: "Start Coverage Test",
            subtitle: "This will begin the network coverage test with your current settings.",
            primaryButtonTitle: "Start test",
            primaryButtonColor: Color("greenButtonBackground"),
            secondaryButtonTitle: "Cancel",
            onPrimaryAction: {},
            onSecondaryAction: {}
        )
        .padding(.horizontal, 20)
    }
}
