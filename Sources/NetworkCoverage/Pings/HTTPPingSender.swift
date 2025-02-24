//
//  HTTPPingSender.swift
//  RMBT
//
//  Created by Jiri Urbasek on 20.02.2025.
//  Copyright © 2025 appscape gmbh. All rights reserved.
//

import Foundation

struct HTTPPingSender: /*PingsSequence.*/PingSending {
    let pingURL: URL
    let urlSession: URLSession

    func initiatePingSession() async throws {}

    func sendPing(in session: Void) async throws(PingSendingError) {
        let request = URLRequest(url: pingURL, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData)
        do {
            _ = try await urlSession.data(for: request)
        } catch {
            throw .networkIssue
        }
    }
}
