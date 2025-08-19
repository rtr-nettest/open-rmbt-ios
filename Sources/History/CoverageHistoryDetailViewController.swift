//
//  CoverageHistoryDetailViewController.swift
//  RMBT
//
//  Created by Jiri Urbasek on 18/08/2025.
//  Copyright © 2025 appscape gmbh. All rights reserved.
//

import UIKit
import SwiftUI

class CoverageHistoryDetailViewController: UIViewController {
    var coverageResult: RMBTHistoryCoverageResult?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        guard let coverageResult = coverageResult else {
            showErrorAndDismiss("Invalid coverage data")
            return
        }
        
        setupSwiftUIView(with: coverageResult)
    }
    
    private func showErrorAndDismiss(_ message: String) {
        let alert = UIAlertController(
            title: "Error",
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            self.navigationController?.popViewController(animated: true)
        })
        present(alert, animated: true)
    }
    
    private func setupSwiftUIView(with result: RMBTHistoryCoverageResult) {
        let swiftUIView = CoverageHistoryDetailView(coverageResult: result)
        let hostingController = UIHostingController(rootView: swiftUIView)
        
        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.didMove(toParent: self)
        
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
}