//
//  TestExportFormat.swift
//  RMBT
//
//  Created by Jiri Urbasek on 3/15/24.
//  Copyright © 2024 appscape gmbh. All rights reserved.
//

import Foundation

enum TestExportFormat {
    case pdf, xlsx, csv
}

extension TestExportFormat {
    var urlPath: String {
        switch self {
        case .pdf: "/export/pdf/de"
        case .xlsx, .csv: "/opentests/search"
        }
    }

    func httpBody(openTestUUIDs: [String], maxResults: Int? = nil) -> Data? {
        let uuidList = openTestUUIDs.joined(separator: ",")
        let maxResultsStr = maxResults.map { ",maxResults=\($0)" } ?? ""

        return switch self {
        case .pdf:
            Data("open_test_uuid=\(uuidList)".utf8)

        case .xlsx, .csv:
            Data("open_test_uuid=\(uuidList)&format=\(format)\(maxResultsStr)".utf8)
        }
    }

    private var format: String {
        switch self {
        case .pdf: ""
        case .xlsx: "xlsx"
        case .csv: "csv"
        }
    }

    func downloadRequest(baseURL: URL, openTestUUIDs: [String], maxResults: Int? = nil) -> URLRequest {
        var request = URLRequest(url: baseURL.appending(path: urlPath))
        request.httpMethod = "POST"
        request.httpBody = httpBody(openTestUUIDs: openTestUUIDs, maxResults: maxResults)

        return request
    }
}
