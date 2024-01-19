//
//  RMBTStatsViewController.swift
//  RMBT
//
//  Created by Sergey Glushchenko on 25.07.2021.
//  Copyright © 2021 appscape gmbh. All rights reserved.
//

import UIKit
import WebKit

class RMBTWebViewController: UIViewController {
    fileprivate lazy var webView: WKWebView = {
        let webView = WKWebView()
        webView.translatesAutoresizingMaskIntoConstraints = false
        return webView
    }()
    
    var url: URL?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        navigationController?.isNavigationBarHidden = true

        self.view.addSubview(webView)
        
        NSLayoutConstraint.activate([
            webView.leftAnchor.constraint(equalTo: self.view.leftAnchor),
            webView.rightAnchor.constraint(equalTo: self.view.rightAnchor),
            webView.topAnchor.constraint(equalTo: self.view.topAnchor, constant: 20),
            webView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor)
        ])
        
        loadUrl(url: url)
    }
    
    func loadUrl(url: URL?) {
        guard let url = url else { return }
        
        if isViewLoaded {
            webView.load(URLRequest(url: url))
        } else {
            self.url = url
        }
    }
}

class RMBTStatsWebViewController: RMBTWebViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.navigationItem.title = NSLocalizedString("menu_button_statistics", comment: "")
        
        loadUrl(url: RMBTControlServer.shared.statsURL)
    }
}

    
final class RMBTStatsViewController: UINavigationController {

    private let unloadViewTimeout = 5.0
    
    override var prefersStatusBarHidden: Bool { return true }
    
    private var timer: Timer?
    
    override func awakeFromNib() {
        super.awakeFromNib()
        
        self.tabBarItem.title = " "
        self.tabBarItem.image = .tabImage
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        self.loadWebView()
    }
   
    private func loadWebView() {
        let webView = RMBTStatsWebViewController()
        self.setViewControllers([webView], animated: false)
    }
}

private extension UIImage {
    static let tabImage = UIImage(named: "tab_stats")
}
