//
//  RMBTHistoryResultViewController.swift
//  RMBT
//
//  Created by Sergey Glushchenko on 09.09.2021.
//  Copyright © 2021 appscape gmbh. All rights reserved.
//

import UIKit
import TUSafariActivity
import CoreLocation

final class RMBTHistoryResultViewController: UIViewController {

    enum Section {
        case map
        case network
        case basicInfo
        case speedGraphs
        case title(_ title: String)
        case qoe
        case netInfo
        case qos
        case testDetails
        case exportButtons
    }
    
    @IBOutlet private weak var tableView: UITableView!
    @IBOutlet private weak var shareButton: UIBarButtonItem!
    @IBOutlet private weak var loadingIndicatorView: UIActivityIndicatorView!
    
    public var historyResult: RMBTHistoryResult?
    public var isShowingLastResult = false
    
    private var sections: [Section] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()

        self.title = self.historyResult?.timeStringIn24hFormat
        
        self.tableView.register(UINib(nibName: RMBTHistoryMapCell.ID, bundle: nil), forCellReuseIdentifier: RMBTHistoryMapCell.ID)
        self.tableView.register(UINib(nibName: RMBTHistoryNetworkCell.ID, bundle: nil), forCellReuseIdentifier: RMBTHistoryNetworkCell.ID)
        self.tableView.register(UINib(nibName: RMBTHistoryBasicInfoCell.ID, bundle: nil), forCellReuseIdentifier: RMBTHistoryBasicInfoCell.ID)
        self.tableView.register(UINib(nibName: RMBTHistorySpeedGrapshCell.ID, bundle: nil), forCellReuseIdentifier: RMBTHistorySpeedGrapshCell.ID)
        self.tableView.register(UINib(nibName: RMBTHistoryTitleCell.ID, bundle: nil), forCellReuseIdentifier: RMBTHistoryTitleCell.ID)
        self.tableView.register(UINib(nibName: RMBTQOEListCell.ID, bundle: nil), forCellReuseIdentifier: RMBTQOEListCell.ID)
        self.tableView.register(UINib(nibName: RMBTNetInfoListCell.ID, bundle: nil), forCellReuseIdentifier: RMBTNetInfoListCell.ID)
        self.tableView.register(UINib(nibName: RMBTQOSListCell.ID, bundle: nil), forCellReuseIdentifier: RMBTQOSListCell.ID)
        self.tableView.register(UINib(nibName: RMBTTestDetailTitleCell.ID, bundle: nil), forCellReuseIdentifier: RMBTTestDetailTitleCell.ID)
        self.tableView.register(UINib(nibName: RMBTTestExportCell.ID, bundle: nil), forCellReuseIdentifier: RMBTTestExportCell.ID)

        self.tableView.contentInset = UIEdgeInsets(top: 20, left: 0, bottom: 10, right: 0)
        
        self.fetchHistoryResultInformation()
        self.prepareSections()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isMovingFromParent, isShowingLastResult, let tabCtrl = tabBarController {
            tabCtrl.selectedIndex = 0
            DispatchQueue.main.async { [weak self] in
                guard let self = self else {return}
                self.navigationController?.popToRootViewController(animated: false)
            }
        }
    }
    
    private func prepareSections() {
        var sections: [Section] = []
        guard let historyResult = self.historyResult else {
            self.sections = []
            self.tableView.reloadData()
            return
        }
        
        if CLLocationCoordinate2DIsValid(historyResult.coordinate) {
            sections.append(.map)
        }
        
        if historyResult.netItems.count > 0 {
            sections.append(.network)
        }
        
        sections.append(.basicInfo)
        
        if (historyResult.downloadGraph != nil) || (historyResult.uploadGraph != nil) || (historyResult.pingGraph != nil) {
            sections.append(.speedGraphs)
        }
        
        if historyResult.qoeClassificationItems.count > 0 ||
            historyResult.netItems.count > 0 ||
            historyResult.qosResults?.count ?? 0 > 0 {
            sections.append(.title(NSLocalizedString("Weitere Details", comment: "")))
            
            if historyResult.netItems.count > 0 {
                sections.append(.netInfo)
            }

            if historyResult.qoeClassificationItems.count > 0 {
                sections.append(.qoe)
            }
            
            if historyResult.qosResults?.count ?? 0 > 0 {
                sections.append(.qos)
            }
        }
        
        if historyResult.fullDetailsItems?.count ?? 0 > 0 {
            sections.append(.testDetails)
        }

        if historyResult.openTestUuid != nil {
            sections.append(.title(NSLocalizedString("Export data", comment: "")))
            sections.append(.exportButtons)
        }

        self.sections = sections
        self.tableView.reloadData()
    }
    
    private func fetchHistoryResultInformation() {
        self.historyResult?.ensureBasicDetails(complete: { [weak self] _, error in
            guard let self = self else { return }
            guard error == nil else {
                let text = "\(NSLocalizedString("Couldn't connect to test server.", comment: "")). (\(String(describing: error?.localizedDescription)))"
                UIAlertController.presentAlert(title: NSLocalizedString("Error", comment: "Alert view title"),
                                               text: text,
                                               cancelTitle: NSLocalizedString("input_setting_dialog_cancel", comment: ""),
                                               otherTitle: NSLocalizedString("Try Again", comment: "Alert view title"),
                                               cancelAction: { _ in
                                                    self.navigationController?.popViewController(animated: true)
                                               },
                                               otherAction: { _ in
                                                self.fetchHistoryResultInformation()
                })
                return
            }
            
            guard let historyResult = self.historyResult else { return }
            guard historyResult.dataState != .index else {
                Log.logger.error("Result not filled with basic data")
                return
            }
            
            self.title = historyResult.timeStringIn24hFormat
            
            var items: [Any] = []
            
            for item in historyResult.measurementItems ?? [] {
                items.append(item)
            }

            historyResult.ensureSpeedGraph(success: { [weak self] in
                self?.prepareSections()
            })
            
            if CLLocationCoordinate2DIsValid(historyResult.coordinate) {
                self.sections.append(.map)
            }
            
            if historyResult.netItems.count > 0 {
                self.sections.append(.network)
            }
            
            self.sections.append(.basicInfo)
            
            self.sections.append(.title(NSLocalizedString("Weitere Details", comment: "")))
            
            if historyResult.netItems.count > 0 {
                self.sections.append(.netInfo)
            }
            
            if historyResult.qoeClassificationItems.count > 0 {
                self.sections.append(.qoe)
            }
            
            if historyResult.qosResults?.count ?? 0 > 0 {
                self.sections.append(.qos)
            }
            
            historyResult.ensureFullDetails { [weak self] in
                self?.prepareSections()
            }
            
            self.loadingIndicatorView.stopAnimating()
            self.shareButton.isEnabled = true
            self.prepareSections()
        })
    }
    
    @IBAction private func share(_ sender: Any) {
        var activities: [UIActivity]?
        var items: [Any] = []
        
        guard let historyResult = self.historyResult else { return }
        
        if let text = historyResult.shareText { items.append(text) }
        if let url = historyResult.shareURL {
            items.append(url)
            activities = [TUSafariActivity()]
        }
        
        let activityViewController = UIActivityViewController(activityItems: items, applicationActivities: activities)
        activityViewController.setValue(RMBTHelpers.RMBTAppTitle(), forKey: "subject")
        
        if UIDevice.current.userInterfaceIdiom == .pad {
            activityViewController.popoverPresentationController?.barButtonItem  = self.navigationItem.rightBarButtonItem
        }
        
        self.present(activityViewController, animated: true, completion: nil)
    }
    
    private func presentFullScreenMap(with zoom: Double = 12) {
        guard let result = self.historyResult,
              let navController = UIStoryboard(name: "MainStoryboard", bundle: nil).instantiateViewController(withIdentifier: "kMapNavigationControllerID") as? UINavigationController
        else { return }
        let mapController = navController.topViewController as? RMBTMapViewController
        mapController?.initialLocation = CLLocation(latitude: result.coordinate.latitude, longitude: result.coordinate.longitude)
//        mapController?.initialZoom = zoom
        self.present(navController, animated: true, completion: nil)
    }
    
    private func showQosGroup(_ item: RMBTHistoryQoSGroupResult) {
        self.performSegue(withIdentifier: "show_qos_group", sender: item)
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "show_qos_group",
           let vc = segue.destination as? RMBTHistoryQoSGroupViewController {
            vc.result = sender as? RMBTHistoryQoSGroupResult
            navigationItem.backBarButtonItem = UIBarButtonItem()
        } else if segue.identifier == "show_test_details", let vc = segue.destination as? RMBTHistoryTestDetailsViewController, let historyResult = historyResult, let testDetails = historyResult.fullDetailsItems as? [RMBTHistoryResultItem] {
            vc.testDetails = testDetails
            vc.navigationItem.backBarButtonItem = UIBarButtonItem()
            vc.title = title
        }
    }
}

extension RMBTHistoryResultViewController: UITableViewDelegate, UITableViewDataSource {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return sections.count
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        let section = sections[indexPath.row]
        switch section {
        case .map:
            return 116
        case .network:
            return 73
        case .basicInfo:
            return 36
        case .speedGraphs:
            return 178
        case .title(_):
            return 60
        case .netInfo:
            return CGFloat(60 + (historyResult?.netItems.count ?? 0) * 24)
        case .qoe:
            return CGFloat(60 + (historyResult?.qoeClassificationItems.count ?? 0) * 48)
        case .qos:
            return CGFloat((historyResult?.qosResults?.count ?? 0) * 48)
        case .testDetails:
            return 48
        case .exportButtons:
            return 48
        }
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let historyResult = self.historyResult else {
            return UITableViewCell()
        }
        let section = sections[indexPath.row]
        switch section {
        case .map:
            let mapCell = tableView.dequeueReusableCell(withIdentifier: RMBTHistoryMapCell.ID, for: indexPath) as! RMBTHistoryMapCell
            mapCell.coordinate = historyResult.coordinate
            mapCell.selectionStyle = .none
            mapCell.onFullScreenHandler = { [weak self] zoom in
                self?.presentFullScreenMap(with: zoom)
            }
            return mapCell
        case .network:
            let networkCell = tableView.dequeueReusableCell(withIdentifier: RMBTHistoryNetworkCell.ID, for: indexPath) as! RMBTHistoryNetworkCell
            networkCell.networkName = historyResult.wlanSSID
            networkCell.networkType = historyResult.networkTypeServerDescription
            networkCell.selectionStyle = .none
            return networkCell
        case .basicInfo:
            let networkCell = tableView.dequeueReusableCell(withIdentifier: RMBTHistoryBasicInfoCell.ID, for: indexPath) as! RMBTHistoryBasicInfoCell
            networkCell.pingValue = historyResult.shortestPingMillisString
            networkCell.pingIcon.tintColor = .byResultClass(historyResult.pingClass)
            networkCell.downloadValue = historyResult.downloadSpeedMbpsString
            networkCell.downIcon.tintColor = .byResultClass(historyResult.downloadSpeedClass)
            networkCell.uploadValue = historyResult.uploadSpeedMbpsString
            networkCell.upIcon.tintColor = .byResultClass(historyResult.uploadSpeedClass)
            networkCell.signalValue = historyResult.signal?.stringValue
            networkCell.signalIcon.tintColor = .byResultClass(historyResult.signalClass)
            networkCell.selectionStyle = .none
            return networkCell
        case .speedGraphs:
            let speedGraphsCell = tableView.dequeueReusableCell(withIdentifier: RMBTHistorySpeedGrapshCell.ID, for: indexPath) as! RMBTHistorySpeedGrapshCell
            var graphs: [(title: String, value: NSObject)] = []
            if let graph = historyResult.downloadGraph {
                graphs.append(("Download", graph))
            }
            if let graph = historyResult.uploadGraph {
                graphs.append(("Upload", graph))
            }
            if let graph = historyResult.pingGraph {
                graphs.append(("Ping", graph))
            }
            speedGraphsCell.graphs = graphs
            speedGraphsCell.selectionStyle = .none
            return speedGraphsCell
        case .title(let title):
            let titleCell = tableView.dequeueReusableCell(withIdentifier: RMBTHistoryTitleCell.ID, for: indexPath) as! RMBTHistoryTitleCell
            titleCell.title = title
            titleCell.selectionStyle = .none
            return titleCell
        case .netInfo:
            let netInfoCell = tableView.dequeueReusableCell(withIdentifier: RMBTNetInfoListCell.ID, for: indexPath) as! RMBTNetInfoListCell
            netInfoCell.title = NSLocalizedString("Network", comment: "")
            netInfoCell.items = historyResult.netItems
            netInfoCell.selectionStyle = .none
            return netInfoCell
        case .qoe:
            let qoeCell = tableView.dequeueReusableCell(withIdentifier: RMBTQOEListCell.ID, for: indexPath) as! RMBTQOEListCell
            qoeCell.title = NSLocalizedString("Qualität", comment: "")
            qoeCell.items = historyResult.qoeClassificationItems
            qoeCell.selectionStyle = .none
            return qoeCell
        case .qos:
            let qosCell = tableView.dequeueReusableCell(withIdentifier: RMBTQOSListCell.ID, for: indexPath) as! RMBTQOSListCell
            qosCell.items = historyResult.qosResults ?? []
            qosCell.selectionStyle = .none
            qosCell.onQosSelectHandler = { [weak self] item in
                self?.showQosGroup(item)
            }
            return qosCell
        case .testDetails:
            let cell = tableView.dequeueReusableCell(withIdentifier: RMBTTestDetailTitleCell.ID, for: indexPath)
            cell.accessoryType = .disclosureIndicator
            return cell
        case .exportButtons:
            let cell = tableView.dequeueReusableCell(withIdentifier: RMBTTestExportCell.ID, for: indexPath) as! RMBTTestExportCell
            if let testUUID = historyResult.openTestUuid {
                cell.configure(
                    with: [testUUID],
                    onExportedPDFFile: { [weak self] in
                        self?.openFile(url: $0, historyResult: historyResult, testUUID: testUUID, fileExtension: "pdf")
                    },
                    onExportedXLSXFile: { [weak self] in
                        self?.openFile(url: $0, historyResult: historyResult, testUUID: testUUID, fileExtension: "xlsx")
                    },
                    onExportedCSVFile: { [weak self] in
                        self?.openFile(url: $0, historyResult: historyResult, testUUID: testUUID, fileExtension: "csv")
                    },
                    onFailure: nil
                )
            }
            return cell

        }
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let section = sections[indexPath.row]
        switch(section) {
        case .testDetails:
            tableView.deselectRow(at: indexPath, animated: true)
            performSegue(withIdentifier: "show_test_details", sender: nil)
        default:
            return
        }
    }
   
}

private extension RMBTHistoryResultViewController {

    func openFile(url: URL, historyResult: RMBTHistoryResult, testUUID: String, fileExtension: String) {
        let pdfViewController = RMBTFilePreviewViewController()
        let fileService = FilePreviewService()
        if let fileURL = try? fileService.temporarilySave(
            fileURL: url,
            withName: (historyResult.timeStringIn24hFormat ?? testUUID) + "." + fileExtension
        ) {
            pdfViewController.configure(fileURLs: [fileURL])
            navigationController?.present(pdfViewController, animated: true)
        }
    }

}
