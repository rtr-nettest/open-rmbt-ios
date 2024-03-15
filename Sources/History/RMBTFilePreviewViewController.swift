//
//  RMBTFilePreviewViewController.swift
//  RMBT
//
//  Created by Jiri Urbasek on 3/13/24.
//  Copyright © 2024 appscape gmbh. All rights reserved.
//

import UIKit
import QuickLook

class RMBTFilePreviewViewController: QLPreviewController, QLPreviewControllerDataSource {

    private var fileURLs: [URL] = []

    func configure(fileURLs: [URL]) {
        dataSource = self

        self.fileURLs = fileURLs
    }

    func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
        fileURLs.count
    }

    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> any QLPreviewItem {
        fileURLs[index] as QLPreviewItem
    }
}

final class FilePreviewService {
    enum Failure: Error {
        case couldNotSaveFile
    }

    private let tmpDirectoryPath: String = NSTemporaryDirectory()

    func temporarilySave(pdfData: Data, withName fileName: String) throws -> URL {
        let fileNameLocalPath = tmpDirectoryPath + fileName

        if FileManager.default.createFile(atPath: fileNameLocalPath, contents: pdfData) {
            return URL(fileURLWithPath: fileNameLocalPath)
        } else {
            throw Failure.couldNotSaveFile
        }
    }

    func temporarilySave(fileURL: URL, withName fileName: String) throws -> URL {
        let fileNameLocalPath = tmpDirectoryPath + fileName

        do {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: fileNameLocalPath))
            try FileManager.default.copyItem(at: fileURL, to: URL(fileURLWithPath: fileNameLocalPath))
        } catch {
            print("\(error)")
        }
        return URL(fileURLWithPath: fileNameLocalPath)
    }
}
