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

    func httpBody(openTestUUID: String) -> Data? {
        switch self {
        case .pdf:
            Data("open_test_uuid=\(openTestUUID)".utf8)

        case .xlsx, .csv:
            Data("open_test_uuid=\(openTestUUID)&format=\(format)".utf8)
        }
    }

    private var format: String {
        switch self {
        case .pdf: ""
        case .xlsx: "xslx"
        case .csv: "csv"
        }
    }

    func downloadRequest(baseURL: URL, openTestUUID: String) -> URLRequest {
        var request = URLRequest(url: baseURL.appending(path: urlPath))
        request.httpMethod = "POST"
        request.httpBody = httpBody(openTestUUID: openTestUUID)

        return request
    }
}
