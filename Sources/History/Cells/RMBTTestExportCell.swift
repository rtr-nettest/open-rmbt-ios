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
    func exportXLSX(openTestUUID: String) async throws -> URL
    func exportCSV(openTestUUID: String) async throws -> URL
}

class RMBTTestExportCell: UITableViewCell {
    enum Failure: Error {
        case missingOpenTestUUID
        case exportError(Error)
    }

    static let ID = "RMBTTestExportCell"

    private let tint = UIColor(named: "tintColor")

    @IBOutlet weak var pdfButton: UIButton!
    @IBOutlet weak var xlsxButton: UIButton!
    @IBOutlet weak var csvButton: UIButton!

    private var openTestUUID: String?
    private let exportService: TestExporting = RMBTControlServer.shared
    private var onExportedPDFFile: ((URL) -> Void)?
    private var onExportedXLSXFile: ((URL) -> Void)?
    private var onExportedCSVFile: ((URL) -> Void)?
    private var onFailure: ((Failure) -> Void)?

    func configure(
        with openTestUUID: String,
        onExportedPDFFile: @escaping ((URL) -> Void),
        onExportedXLSXFile: @escaping  ((URL) -> Void),
        onExportedCSVFile: @escaping ((URL) -> Void),
        onFailure: ((Failure) -> Void)?
    ) {
        self.openTestUUID = openTestUUID
        self.onExportedPDFFile = onExportedPDFFile
        self.onExportedXLSXFile = onExportedXLSXFile
        self.onExportedCSVFile = onExportedCSVFile
        self.onFailure = onFailure
    }

    override func prepareForReuse() {
        configureButtons()
    }

    override func awakeFromNib() {
        configureButtons()
    }

    private func configureButtons() {
        [(pdfButton, "pdf"), (xlsxButton, "xlsx"), (csvButton, "csv")].forEach {
            $0.0.configuration?.background.backgroundColor = .clear
            $0.0.configuration?.background.strokeColor = tint
            $0.0.tintColor = tint
            $0.0.configuration?.showsActivityIndicator = false
            $0.0.configuration?.imagePadding = 4
            $0.0.configuration?.contentInsets = .init(top: 4, leading: 8, bottom: 4, trailing: 8)
            $0.0.configuration?.title = $0.1.uppercased()
            $0.0.configuration?.image = .init(named: "filetype-\($0.1)-icon")
            $0.0.accessibilityLabel = NSLocalizedString("Export to", comment: "") + " \($0.1)" // TODO: localize
        }
    }

    @IBAction func pdfButtonTouched(_ sender: UIButton) {
        guard let openTestUUID else {
            onFailure?(.missingOpenTestUUID)
            return
        }
        let title = sender.showActivity()

        Task { @MainActor in
            do {
                let pdf = try await exportService.exportPDF(openTestUUID: openTestUUID)
                onExportedPDFFile?(pdf)
            } catch {
                onFailure?(.exportError(error))
            }
            sender.hideActivity(title: title)
        }
    }

    @IBAction func xlsxButtonTouched(_ sender: UIButton) {
        guard let openTestUUID else {
            onFailure?(.missingOpenTestUUID)
            return
        }
        let title = sender.showActivity()

        Task { @MainActor in
            do {
                let pdf = try await exportService.exportXLSX(openTestUUID: openTestUUID)
                onExportedXLSXFile?(pdf)
            } catch {
                onFailure?(.exportError(error))
            }
            sender.hideActivity(title: title)
        }
    }

    @IBAction func csvButtonTouched(_ sender: UIButton) {
        guard let openTestUUID else {
            onFailure?(.missingOpenTestUUID)
            return
        }
        let title = sender.showActivity()

        Task { @MainActor in
            do {
                let pdf = try await exportService.exportCSV(openTestUUID: openTestUUID)
                onExportedCSVFile?(pdf)
            } catch {
                onFailure?(.exportError(error))
            }
            sender.hideActivity(title: title)
        }
    }
}

private extension UIButton {
    func showActivity() -> String? {
        configuration?.showsActivityIndicator = true
        let title = configuration?.title
        configuration?.title = nil

        return title
    }

    func hideActivity(title: String?) {
        configuration?.showsActivityIndicator = false
        configuration?.title = title
    }
}

extension RMBTControlServer: TestExporting {
    func exportPDF(openTestUUID: String) async throws -> URL {
        try await getTestExport(into: .pdf, openTestUUID: openTestUUID)
    }

    func exportXLSX(openTestUUID: String) async throws -> URL {
        try await getTestExport(into: .xlsx, openTestUUID: openTestUUID)
    }

    func exportCSV(openTestUUID: String) async throws -> URL {
        try await getTestExport(into: .csv, openTestUUID: openTestUUID)
    }
}
