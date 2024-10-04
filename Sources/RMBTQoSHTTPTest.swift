//
//  RMBTQoSHTTPTest.swift
//  RMBT
//
//  Created by Sergey Glushchenko on 10.12.2021.
//  Copyright © 2021 appscape gmbh. All rights reserved.
//

import UIKit

class RMBTQoSHTTPTest: RMBTQoSTest, @unchecked Sendable {

    private var url: String?
    private var range: String?
    
    private var responseFingerprint: String?
    private var responseAllHeaders: String?
    private var responseStatusCode: Int?
    private var responseExpectedContentLength: Int64?
    
    private var task: URLSessionDataTask?
    private lazy var session: URLSession? = {
        return URLSession(configuration: URLSessionConfiguration.ephemeral, delegate: self, delegateQueue: nil)
    }()
    
    override init?(with params: [String : Any]) {
        super.init(with: params)
        url = params["url"] as? String
        range = params["range"] as? String
    }
    
    override func main() {
        let doneSem = DispatchSemaphore(value: 0)
        
        guard let url = URL(string: self.url ?? "") else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = TimeInterval(self.timeoutSeconds())
        
        if let range = self.range {
            request.addValue(range, forHTTPHeaderField: "Range")
        }

        task = session?.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            if error == nil,
                let httpResponse = response as? HTTPURLResponse {
                self.responseStatusCode = httpResponse.statusCode
                self.responseExpectedContentLength = httpResponse.expectedContentLength
                self.responseFingerprint = data?.MD5HexString ?? ""
                
                var concatHeaders = ""
                httpResponse.allHeaderFields.forEach { item in
                    concatHeaders.append("\(item.key): \(item.value)\n")
                }
                self.responseAllHeaders = concatHeaders
            } else {
                // TODO: timeout
                self.responseFingerprint = "ERROR"
                self.responseStatusCode = 0
                self.responseExpectedContentLength = 0
                self.responseAllHeaders = ""
            }
            
            self.session?.finishTasksAndInvalidate()
            self.session = nil
            doneSem.signal()
        }
        task?.resume()
        
        _ = doneSem.wait(timeout: .now() + TimeInterval(self.timeoutSeconds()))
    }
    
    override var result: [String: Any] {
        return [
            "http_objective_range": RMBTValueOrNull(range),
            "http_objective_url": RMBTValueOrNull(url),
            "http_result_status": RMBTValueOrNull(responseStatusCode),
            "http_result_length": RMBTValueOrNull(responseExpectedContentLength),
            "http_result_header": RMBTValueOrNull(responseAllHeaders),
            "http_result_hash": RMBTValueOrNull(responseFingerprint)
        ]
    }
    
    override var description: String {
        return String(format:"RMBTQoSHTTPTest (uid=%@, cg=%ld, %@/%@)",
                self.uid,
                self.concurrencyGroup,
                url ?? "",
                range ?? "")
    }
}

extension RMBTQoSHTTPTest: URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
