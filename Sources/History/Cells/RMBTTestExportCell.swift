//
//  RMBTTestExportCell.swift
//  RMBT
//
//  Created by Jiri Urbasek on 3/13/24.
//  Copyright © 2024 appscape gmbh. All rights reserved.
//

import UIKit

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
    private let exportService: TestExporting = TestExportServiceMock()
    private var onExportedPDFFile: ((Data) -> Void)?
    private var onFailure: ((Failure) -> Void)?

    func configure(with openTestUUID: String, onExportedPDFFile: ((Data) -> Void)?, onFailure: ((Failure) -> Void)?) {
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

// MARK -

protocol TestExporting {
    func exportPDF(openTestUUID: String) async throws -> Data
}

final class TestExportService: TestExporting {
    func exportPDF(openTestUUID: String) async throws -> Data {
        .init()
    }
}

final class TestExportServiceMock: TestExporting {
    func exportPDF(openTestUUID: String) async throws -> Data {
        let pdfPageFrame = await UIApplication.shared.keyWindow!.bounds
        let pdfData = NSMutableData()
        UIGraphicsBeginPDFContextToData(pdfData, pdfPageFrame, nil)
        UIGraphicsBeginPDFPageWithInfo(pdfPageFrame, nil)
        guard let pdfContext = UIGraphicsGetCurrentContext() else {
            throw NSError(domain: "culd not create graphic context", code: 1)
        }
        await UIApplication.shared.keyWindow!.layer.render(in: pdfContext)
        UIGraphicsEndPDFContext()

        try await Task.sleep(for: .seconds(2))

        return pdfData as Data
    }
}
