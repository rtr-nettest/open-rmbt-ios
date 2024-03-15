//
//  RMBTTestExportCell.swift
//  RMBT
//
//  Created by Jiri Urbasek on 3/13/24.
//  Copyright © 2024 appscape gmbh. All rights reserved.
//

import UIKit

protocol TestExporting {
    func exportPDF(openTestUUID: String) async throws -> URL
}

class RMBTTestExportCell: UITableViewCell {
    enum Failure: Error {
        case missingOpenTestUUID
        case exportError(Error)
    }

    static let ID = "RMBTTestExportCell"

    @IBOutlet weak var pdfButton: UIButton!
    @IBOutlet weak var xlsxButton: UIButton!
    @IBOutlet weak var csvButton: UIButton!

    private var openTestUUID: String?
    private let exportService: TestExporting = RMBTControlServer.shared
    private var onExportedPDFFile: ((URL) -> Void)?
    private var onFailure: ((Failure) -> Void)?

    func configure(with openTestUUID: String, onExportedPDFFile: ((URL) -> Void)?, onFailure: ((Failure) -> Void)?) {
        self.openTestUUID = openTestUUID
        self.onExportedPDFFile = onExportedPDFFile
        self.onFailure = onFailure
    }

    override func prepareForReuse() {
        [pdfButton, xlsxButton, csvButton].forEach {
            $0.isEnabled = true
            $0.tintColor = .rmbt_color(withRGBHex: 0x78ED03)
        }
    }

    @IBAction func pdfButtonTouched(_ sender: UIButton) {
        guard let openTestUUID else {
            onFailure?(.missingOpenTestUUID)
            return
        }

        var configuration = UIButton.Configuration.tinted()
        configuration.showsActivityIndicator = true

        pdfButton.configuration = configuration

        Task { @MainActor in
            do {
                let pdf = try await exportService.exportPDF(openTestUUID: openTestUUID)
                onExportedPDFFile?(pdf)
            } catch {
                onFailure?(.exportError(error))
            }
            configuration.showsActivityIndicator = false
            configuration.title = "PDF"
            pdfButton.configuration = configuration
        }
    }

    @IBAction func xlsxButtonTouched(_ sender: UIButton) {
    }

    @IBAction func csvButtonTouched(_ sender: UIButton) {
    }
}

extension RMBTControlServer: TestExporting {
    func exportPDF(openTestUUID: String) async throws -> URL {
        try await getTestExport(into: .pdf, openTestUUID: openTestUUID)
    }
}
