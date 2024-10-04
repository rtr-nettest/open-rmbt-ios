//
//  RMBTQoSWebTest.swift
//  RMBT
//
//  Created by Sergey Glushchenko on 10.12.2021.
//  Copyright © 2021 appscape gmbh. All rights reserved.
//

import UIKit
@preconcurrency import WebKit

enum RMBTQosWebTestURLProtocolResultKeys: String {
    case status = "status"
    case rxBytes = "rx"
}

class RMBTQoSWebTest: RMBTQoSTest, @unchecked Sendable {    
    private var url: String?
    private var webView: WKWebView?
    private var requestCount: UInt = 0
    
    private var sem: DispatchSemaphore?
    private var startedAt: UInt64 = 0
    private var duration: UInt64 = 0
    
    private var protocolResult: [String: Any] = [:]
    private var rxBytesCount: Int64 = 0
    private var statusCode: Int = 0
    
    override init?(with params: [String : Any]) {
        url = params["url"] as? String
        super.init(with: params)
    }
    
    override func main() {
        startedAt = 0
        statusCode = 200
        rxBytesCount = 0
        sem = DispatchSemaphore(value: 0)
        DispatchQueue.main.sync { [weak self] in
            guard let self = self,
                  let url = URL(string: self.url ?? "")
            else { return }
            //_webView = [[WKWebView alloc] initWithFrame:CGRectMake(0, 0, 1900, 1200) configuration:[]
            self.webView = WKWebView()
            self.webView?.navigationDelegate = self
            let request = URLRequest(url: url)
            self.webView?.load(request)
        }

        let result = sem?.wait(timeout: .now() + Double(self.timeoutNanos))
        if result == .timedOut {
            self.status = .timeout
        } else {
            self.status = .ok
            duration = RMBTHelpers.RMBTCurrentNanos() - startedAt
        }

        protocolResult = [
            RMBTQosWebTestURLProtocolResultKeys.status.rawValue: statusCode,
            RMBTQosWebTestURLProtocolResultKeys.rxBytes.rawValue: rxBytesCount,
        ]

        DispatchQueue.main.sync {
            self.webView?.stopLoading()
            self.webView = nil
        }
    }
    
    func maybeDone() {
        if self.status == .timeout {
            // Already timed out
            return
        }
        
        assert(requestCount > 0)
        assert(sem != nil)
        
        requestCount -= 1
        
        if (requestCount == 0) {
            sem?.signal()
        }
    }
    
    override var result: [String: Any] {
        return [
            "website_objective_url": RMBTValueOrNull(url),
            "website_objective_timeout": self.timeoutNanos,
            "website_result_info": RMBTValueOrNull(self.statusName()),
            "website_result_duration": duration,
            "website_result_status": RMBTValueOrNull(protocolResult[RMBTQosWebTestURLProtocolResultKeys.status.rawValue]),
            "website_result_rx_bytes": RMBTValueOrNull(protocolResult[RMBTQosWebTestURLProtocolResultKeys.rxBytes.rawValue]),
            "website_result_tx_bytes": NSNull()
        ];
    }
    
    override var description: String {
        return String(format: "RMBTQoSWebTest (uid=%@, cg=%ld, url=%@)",
                      self.uid,
                      self.concurrencyGroup,
                      self.url ?? "")
    }
}

extension RMBTQoSWebTest: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        assert(self.status == .unknown)
        if (startedAt == 0) {
            startedAt = RMBTHelpers.RMBTCurrentNanos()
        }
        decisionHandler(.allow)
    }
    
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        requestCount += 1
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        self.maybeDone()
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        self.status = .error
        self.maybeDone()
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        
        let currentURLString = navigationResponse.response.url?.absoluteString ?? ""
        //Small hack to check is equal urls or not.
        //Sometimes url can be with slash in the end and without slash and it's different url
        //Example: http://google.com/ and http://google.com is not equal because different slash
        //We remove all slashes from urls and http:google.com is equal http:google.com
        
        let currentURLStringWithoutSlash = currentURLString.replacingOccurrences(of: "/", with: "")
    
        let URLStringWithoutSlash = url?.replacingOccurrences(of: "/", with: "") ?? ""
        
        if currentURLStringWithoutSlash == URLStringWithoutSlash,
            let response = navigationResponse.response as? HTTPURLResponse {
            statusCode = response.statusCode
        }
        
        if let response = navigationResponse.response as? HTTPURLResponse,
           response.expectedContentLength != -1 {
            rxBytesCount = rxBytesCount + response.expectedContentLength
        }

        decisionHandler(.allow);
    }
}
