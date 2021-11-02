//
//  RMBTHistoryIndexViewController.swift
//  RMBT
//
//  Created by Sergey Glushchenko on 04.09.2021.
//  Copyright © 2021 appscape gmbh. All rights reserved.
//

import UIKit

final class RMBTHistoryIndex2ViewController: UIViewController {
    enum State {
        case loading
        case empty
        case hasEntries
    }
    
    enum ActionSheetState: Int {
        case kSyncSheetRequestCodeButtonIndex = 1
        case kSyncSheetEnterCodeButtonIndex = 2
    }
    
    private let kBatchSize = 25

    @IBOutlet weak var headerView: UIView!
    
    @IBOutlet weak var topFilterConstaint: NSLayoutConstraint!
    @IBOutlet weak var filterContainer: UIView!
    
    @IBOutlet weak var tableView: UITableView!
    @IBOutlet weak var loadingContainerView: UIView!
    @IBOutlet weak var filterButtonItem: UIBarButtonItem!
    @IBOutlet weak var emptyLabel: UILabel!
    
    private lazy var filterView: RMBTHistoryFilterView = {
        let view = RMBTHistoryFilterView.view()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.onFilterChanged = { [weak self] filters in
            guard let self = self else { return }
            var validFilters: [String:[String]] = [:]
            
            for filter in self.allFilters {
                if let filtersByKey = filters[filter.key], filtersByKey.count > 0 {
                    validFilters[filter.key] = filtersByKey
                } else {
                    validFilters[filter.key] = filter.value
                }
            }
            
            self.activeFilters = validFilters
        }
        return view
    }()
    
    private var firstAppearance: Bool = false
    
    private var tableViewController: UITableViewController?
    
    var showingLastTestResult = false
    
    var loading = false
    
    private var testResults: [RMBTHistoryResult] = []
    private var nextBatchIndex: Int = 0
    
    private var enterCodeAlertView: UIAlertView?
    
    override var preferredStatusBarStyle: UIStatusBarStyle { return .lightContent }
    
    var activeFilters: [String: [String]] = [:] {
        didSet {
            self.changedFilters()
        }
    }
    
    var allFilters: [String: [String]] = [:]
    
    private var state: State = .loading {
        didSet {
            self.loadingContainerView.isHidden = true
            self.emptyLabel.isHidden = true
            self.tableView.isHidden = true
            self.filterButtonItem.isEnabled = false
            self.headerView.isHidden = false

            if (state == .empty) {
                self.emptyLabel.isHidden = false
                self.headerView.isHidden = true
                self.firstAppearance = true
            } else if (state == .hasEntries) {
                self.tableView.isHidden = false
                self.filterButtonItem.isEnabled = true
            } else if (state == .loading) {
                self.loadingContainerView.isHidden = false
            }
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.navigationItem.title = .title
        self.setNeedsStatusBarAppearanceUpdate()

        firstAppearance = true

        // Add footer padding to compensate for tab bar
        let footerView = UIView(frame: CGRect(x: 0,y: 0,width: 0,height: self.tabBarController?.tabBar.frame.height ?? 0))
        footerView.backgroundColor = UIColor.clear
        self.tableView.tableFooterView = footerView
        self.tableView.register(UINib(nibName: RMBTHistoryIndexCell.ID, bundle: nil), forCellReuseIdentifier: RMBTHistoryIndexCell.ID)
        self.tableView.register(UINib(nibName: RMBTHistoryLoadingCell.ID, bundle: nil), forCellReuseIdentifier: RMBTHistoryLoadingCell.ID)
        self.tableView.refreshControl = UIRefreshControl()
        self.tableView.refreshControl?.addTarget(self, action: #selector(refreshFromTableView(_:)), for: .valueChanged)
        
        self.filterContainer.addSubview(self.filterView)
        
        NSLayoutConstraint.activate([
            self.filterContainer.leftAnchor.constraint(equalTo: self.filterView.leftAnchor),
            self.filterContainer.topAnchor.constraint(equalTo: self.filterView.topAnchor),
            self.filterContainer.bottomAnchor.constraint(equalTo: self.filterView.bottomAnchor),
            self.filterContainer.rightAnchor.constraint(equalTo: self.filterView.rightAnchor)
        ])
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        if (firstAppearance) {
            firstAppearance = false
        } else if let selectedIndexPath = self.tableView.indexPathForSelectedRow {
            self.tableView.deselectRow(at: selectedIndexPath, animated: true)
        } else if showingLastTestResult {
            // Note: This shouldn't be necessary once we have info required for index view in the
            // test result object. See -displayTestResult.
            showingLastTestResult = false
        }
        self.refresh()
        self.refreshFilters()
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
        
        self.navigationController?.tabBarItem.title = " "
        self.navigationController?.tabBarItem.selectedImage = UIImage(named: "tab_history_selected")
    }
    
    @IBAction func sync(_ sender: Any?) {
        let title = NSLocalizedString("To merge history from two different devices, request the sync code on one device and enter it on another device", comment: "Sync intro text");
        
        let actionSheet = UIActionSheet(title: title,
                                        delegate: self,
                                        cancelButtonTitle: NSLocalizedString("Cancel", comment: "Sync dialog button"),
                                        destructiveButtonTitle: nil,
                                        otherButtonTitles:
                                            NSLocalizedString("Request code", comment: "Sync dialog button"),
                                            NSLocalizedString("Enter code", comment: "Sync dialog button")
                                        )
        actionSheet.show(in: self.view)
    }
    
    @IBAction func updateFilters(_ segue: UIStoryboardSegue) {
        let filterVC = segue.source as? RMBTHistoryFilter2ViewController
        activeFilters = filterVC?.activeFilters ?? [:]
        self.refresh()
    }
    
    public func displayTestResult(_ result: RMBTHistoryResult) {
        self.navigationController?.popToRootViewController(animated: false)

        showingLastTestResult = true
        
        let resultVC = self.storyboard?.instantiateViewController(withIdentifier: "result2_vc") as! RMBTHistoryResult2ViewController
        resultVC.historyResult = result
        
        self.navigationController?.pushViewController(resultVC, animated: false)
    }
    
    @objc private func refreshFromTableView(_ sender: Any) {
        tableViewController?.refreshControl?.beginRefreshing()
        testResults = []
        nextBatchIndex = 0
        getNextBatch()
    }
    
    private func refresh() {
        state = .loading
        testResults = []
        nextBatchIndex = 0
        getNextBatch()
    }
    
    private func changedFilters() {
        var activeFilters: [String: [String]] = [:]
        for filter in self.activeFilters {
            if filter.value.count != self.allFilters[filter.key]?.count {
                activeFilters[filter.key] = filter.value
            }
        }
        filterView.activeFilters = activeFilters
        updateFilterViewPosition()
        refresh()
    }
    
    private func updateFilterViewPosition() {
        var isShow = false
        if (filterView.activeFilters != allFilters) {
            for filters in filterView.activeFilters {
                if filters.value.count > 0 {
                    isShow = true
                    break
                }
            }
        }
        
        self.topFilterConstaint.constant = isShow ? 0 : -self.filterContainer.bounds.height
        UIView.animate(withDuration: 0.3) {
            self.view.layoutIfNeeded()
        }
    }

    private func getNextBatch() {
        loading = true
        let firstBatch = nextBatchIndex == 0
        let offset = nextBatchIndex * kBatchSize
        
        RMBTControlServer.shared.getHistoryWithFilters(filters: activeFilters,
                                                       length: UInt(kBatchSize),
                                                       offset: UInt(offset)) { [weak self] response in
            guard let self = self else { return }
            
            let responses: [HistoryItem] = response.records
            let oldCount = self.testResults.count
            
            var indexPaths: [IndexPath] = []
            var results: [RMBTHistoryResult] = []
            
            for r in responses {
                results.append(RMBTHistoryResult(response: r.json()))
                indexPaths.append(IndexPath(row: oldCount-1 + results.count, section: 0))
            }
            
            // We got less results than batch size, this means this was the last batch
            if (results.count < self.kBatchSize) {
                self.nextBatchIndex = NSNotFound
            } else {
                self.nextBatchIndex += 1
            }
            
            self.testResults.append(contentsOf: results)
            
            if (firstBatch) {
                self.state = self.testResults.count == 0 ? .empty : .hasEntries
            }
            self.tableView.reloadData()
            
            self.loading = false

            self.tableView?.refreshControl?.endRefreshing()
        } error: { error in
            Log.logger.error(error)
        }
    }
    
    private func refreshFilters() {
        // Wait for UUID to be retrieved
        RMBTControlServer.shared.ensureClientUuid { uuid in
            RMBTControlServer.shared.getSettings {
                self.allFilters = RMBTControlServer.shared.historyFilters ?? [:]
                self.activeFilters = self.activeFilters.count > 0 ? self.activeFilters : self.allFilters
            } error: { error in
                Log.logger.error(error)
            }
        } error: { error in
            Log.logger.error(error)
        }
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "show_filter",
           let navController = segue.destination as? UINavigationController,
           let filterVC = navController.topViewController as? RMBTHistoryFilter2ViewController {
            filterVC.allFilters = allFilters
            filterVC.activeFilters = activeFilters
            filterVC.onFilterChanged = { [weak self] filters in
                guard let self = self else { return }
                
                self.activeFilters = filters
            }
        } else if segue.identifier == "show_result",
            let rvc = segue.destination as? RMBTHistoryResult2ViewController {
            rvc.historyResult = sender as? RMBTHistoryResult
        }
    }
    
}

extension RMBTHistoryIndex2ViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        var result = testResults.count
        if (nextBatchIndex != NSNotFound) { result += 1 }
        return result
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 48
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if (indexPath.row >= testResults.count) {
            // Loading cell
            let cell = tableView.dequeueReusableCell(withIdentifier: RMBTHistoryLoadingCell.ID, for: indexPath) as! RMBTHistoryLoadingCell
            return cell
        } else {
            let cell = tableView.dequeueReusableCell(withIdentifier: RMBTHistoryIndexCell.ID, for: indexPath) as! RMBTHistoryIndexCell
            
            let testResult = testResults[indexPath.row]

            let networTypeIcon = RMBTNetworkTypeConstants.networkTypeDictionary[testResult.networkTypeServerDescription]?.icon
            cell.typeImageView.image = networTypeIcon
            cell.dateLabel.text = testResult.timeString
            cell.downloadSpeedLabel.text = testResult.downloadSpeedMbpsString
            cell.uploadSpeedLabel.text = testResult.uploadSpeedMbpsString
            cell.pingLabel.text = testResult.shortestPingMillisString

            return cell
        }
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let result = testResults[indexPath.row]
        self.performSegue(withIdentifier: "show_result", sender: result)
    }
    
    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        if indexPath.row >= (testResults.count - 5) {
            if (!loading && nextBatchIndex != NSNotFound) {
                self.getNextBatch()
            }
        }
    }
}

extension RMBTHistoryIndex2ViewController: UIActionSheetDelegate {
    func actionSheet(_ actionSheet: UIActionSheet, didDismissWithButtonIndex buttonIndex: Int) {
        if (buttonIndex == ActionSheetState.kSyncSheetRequestCodeButtonIndex.rawValue) {
            RMBTControlServer.shared.getSyncCode { response in
                UIAlertView.bk_show(
                    withTitle: NSLocalizedString("Sync Code", comment: "Display code alert title"),
                    message: response.codes?.first?.code,
                    cancelButtonTitle: NSLocalizedString("OK", comment: "Display code alert button"),
                    otherButtonTitles: [NSLocalizedString("Copy code", comment: "Display code alert button")]) { alertView, buttonIndex in
                    if (buttonIndex == 1) {
                        // Copy
                        UIPasteboard.general.string = response.codes?.first?.code
                    } // else just dismiss
                }
            } error: { error in
                Log.logger.error(error)
            }

        } else if (buttonIndex == ActionSheetState.kSyncSheetEnterCodeButtonIndex.rawValue) {
            enterCodeAlertView = UIAlertView(
                title: NSLocalizedString("Enter sync code:", comment: "Sync alert title"),
                message: "",
                delegate: self,
                cancelButtonTitle: NSLocalizedString("Cancel", comment: "Sync alert button"),
                otherButtonTitles: NSLocalizedString("Sync", comment: "Sync alert button")
                )
            enterCodeAlertView?.alertViewStyle = .plainTextInput
            enterCodeAlertView?.show()
        }
    }
}

extension RMBTHistoryIndex2ViewController: UIAlertViewDelegate {
    func alertView(_ alertView: UIAlertView, didDismissWithButtonIndex buttonIndex: Int) {
        if (alertView == enterCodeAlertView && buttonIndex == 1) {
            guard let code = alertView.textField(at: 0)?.text?.uppercased() else { return }

            RMBTControlServer.shared.syncWithCode(code) { response in
                UIAlertView.bk_show(
                    withTitle: NSLocalizedString("Success", comment: "Sync success alert title"),
                    message: NSLocalizedString("History synchronisation was successful.", comment: "Sync success alert msg"),
                    cancelButtonTitle: NSLocalizedString("Reload", comment: "Sync success button"),
                    otherButtonTitles: nil) { _, buttonIndex in
                    self.refresh()
                    self.refreshFilters()
                }
            } error: { error in
                let title = (error as NSError?)?.userInfo["msg_title"] as? String
                let text = (error as NSError?)?.userInfo["msg_text"] as? String
                
                UIAlertView.bk_show(
                    withTitle: title,
                    message: text,
                    cancelButtonTitle: NSLocalizedString("Dismiss", comment: "Alert view button"), otherButtonTitles: []) { _, buttonIndex in
                    
                }
            }
        }
    }
}

private extension String {
    static let title = NSLocalizedString("menu_button_history", comment: "History")
}
