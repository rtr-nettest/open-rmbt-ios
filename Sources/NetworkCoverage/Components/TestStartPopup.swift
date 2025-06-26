//
//  TestStartPopup.swift
//  RMBT
//
//  Created by Jiri Urbasek on 25.06.2025.
//  Copyright 2025 appscape gmbh. All rights reserved.
//

import SwiftUI

struct TestStartPopup: View {
    let title: String
    let subtitle: String
    let onStartTest: () -> Void
    let onCancel: () -> Void

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
                // Start test button
                Button(action: onStartTest) {
                    Text("Start test") // TODO: Localize
                        .font(.callout)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .frame(height: 50)
                        .frame(maxWidth: .infinity)
                        .background(Color("greenButtonBackground"))
                        .cornerRadius(8)
                }

                Button(action: {
                    onCancel()
                }) {
                    Text("text_button_decline")
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

// MARK: - View Modifier
struct TestStartPopupModifier: ViewModifier {
    @Binding var isPresented: Bool
    let title: String
    let subtitle: String
    let onStartTest: () -> Void

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
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    isPresented = false
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
                        TestStartPopup(
                            title: title,
                            subtitle: subtitle,
                            onStartTest: {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    isPresented = false
                                }
                                onStartTest()
                            },
                            onCancel: {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    isPresented = false
                                }
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

// MARK: - View Extension
extension View {
    func testStartPopup(
        isPresented: Binding<Bool>,
        title: String,
        subtitle: String,
        onStartTest: @escaping () -> Void
    ) -> some View {
        modifier(
            TestStartPopupModifier(
                isPresented: isPresented,
                title: title,
                subtitle: subtitle,
                onStartTest: onStartTest
            )
        )
    }
}

#Preview {
    ZStack {
        Color.gray.opacity(0.2)
        TestStartPopup(
            title: "Start Coverage Test",
            subtitle: "This will begin the network coverage test with your current settings.",
            onStartTest: {},
            onCancel: {}
        )
        .padding(.horizontal, 20)
    }
}
