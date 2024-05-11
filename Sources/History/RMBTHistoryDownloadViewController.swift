//
//  RMBTHistoryDownloadViewController.swift
//  RMBT
//
//  Created by Jiri Urbasek on 5/6/24.
//  Copyright © 2024 appscape gmbh. All rights reserved.
//

import UIKit

final class RMBTHistoryDownloadViewController: UIViewController {

    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var tableView: UITableView!

    var openTestUUIDs: [String] = []

    private var activeIndexPaths: Set<IndexPath> = []
    private var allIndexPaths: Set<IndexPath> = []

    override func viewDidLoad() {
        super.viewDidLoad()

        self.tableView.register(UINib(nibName: RMBTTestExportCell.ID, bundle: nil), forCellReuseIdentifier: RMBTTestExportCell.ID)
        
        tableView.tableFooterView = UIView()
        tableView.separatorStyle = .none
    }

    @IBAction func closeButtonClick(_ sender: Any) {
        self.dismiss(animated: true, completion: nil)
    }
}

extension RMBTHistoryDownloadViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        1
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        56
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: RMBTTestExportCell.ID, for: indexPath) as! RMBTTestExportCell
        cell.configure(
            with: openTestUUIDs,
            onExportedPDFFile: { [weak self] in
                self?.openFile(url: $0, asNamed: "all-tests", fileExtension: "pdf")
            },
            onExportedXLSXFile: { [weak self] in
                self?.openFile(url: $0, asNamed: "all-tests", fileExtension: "xlsx")
            },
            onExportedCSVFile: { [weak self] in
                self?.openFile(url: $0, asNamed: "all-tests", fileExtension: "csv")
            },
            onFailure: nil
        )
        return cell
    }
}

extension RMBTHistoryDownloadViewController: RMBTBottomCardProtocol {
    var contentSize: CGSize { return CGSize(width: 0, height: 150) }
}

private extension RMBTHistoryDownloadViewController {
    func openFile(url: URL, asNamed name: String, fileExtension: String) {
        let pdfViewController = RMBTFilePreviewViewController()
        let fileService = FilePreviewService()
        if let fileURL = try? fileService.temporarilySave(
            fileURL: url,
            withName: name + "." + fileExtension
        ) {
            pdfViewController.configure(fileURLs: [fileURL])

            let presentingVC = presentingViewController
            presentingVC?.dismiss(animated: true)
            presentingVC?.present(pdfViewController, animated: true)
        }
    }
}
