//
//  CoverageResultView.swift
//  RMBT
//
//  Created by Claude Code on 7/21/25.
//  Copyright 2024 appscape gmbh. All rights reserved.
//

import SwiftUI

struct CoverageResultView: View {
    let onClose: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Text("Coverage Test Results")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Test completed successfully!")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Text("This is a mock results screen for testing purposes.")
                .font(.body)
                .multilineTextAlignment(.center)
                .padding()
            
            Button(action: onClose) {
                Text("Close")
                    .font(.callout)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .frame(height: 50)
                    .frame(maxWidth: .infinity)
                    .background(Color("greenButtonBackground"))
                    .cornerRadius(8)
            }
            .padding(.horizontal, 32)
            
            Spacer()
        }
        .padding()
        .navigationTitle("Results")
        .navigationBarTitleDisplayMode(.large)
    }
}

#Preview {
    NavigationStack {
        CoverageResultView(onClose: {})
    }
}