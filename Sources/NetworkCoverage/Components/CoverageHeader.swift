//
//  CoverageHeader.swift
//  RMBT
//
//  Created by Jiri Urbasek on 05.08.2025.
//  Copyright © 2025 appscape gmbh. All rights reserved.
//

import SwiftUI

struct CoverageHeader<Content: View>: View {
    struct Action {
        let title: LocalizedStringKey
        let action: () -> Void
    }

    let title: LocalizedStringKey
    let action: Action?
    let isContentEmpty: Bool
    @ViewBuilder var content: () -> Content

    private init(title: LocalizedStringKey, action: Action?, isContentEmpty: Bool, content: @escaping () -> Content) {
        self.title = title
        self.action = action
        self.isContentEmpty = isContentEmpty
        self.content = content
    }

    init(title: LocalizedStringKey, action: Action? = nil, content: @escaping () -> Content) {
        self.init(title: title, action: action, isContentEmpty: false, content: content)
    }

    var body: some View {
        VStack {
            HStack {
                Text(title)
                    .font(.title2)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .fontWeight(.semibold)

                Spacer()

                if let action {
                    Button(action.title, action: action.action)
                        .tint(.brand)
                        .padding(.horizontal, 8)
                }
            }

            if !isContentEmpty {
                Divider()
                content()
            }
        }
        .padding(8)
        .background(Color.white.opacity(0.85))
        .cornerRadius(8)
        .padding(.horizontal, 5) // same padding as Map button
        .padding(.bottom, 8)
    }
}

extension CoverageHeader where Content == EmptyView {
    init(title: LocalizedStringKey, action: Action? = nil) {
        self.init(title: title, action: action, isContentEmpty: true, content: { EmptyView() })
    }
}
