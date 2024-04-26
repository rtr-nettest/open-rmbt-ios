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
        let maxResultsStr = maxResults.map { "&maxResults=\($0)" } ?? ""
        let httpBodyStr: String

        httpBodyStr = switch self {
        case .pdf: 
            "open_test_uuid=\(uuidList)"
        case .xlsx, .csv: 
            "open_test_uuid=\(uuidList)&format=\(format)\(maxResultsStr)"
        }

        return httpBodyStr.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed).map { Data($0.utf8) }
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
