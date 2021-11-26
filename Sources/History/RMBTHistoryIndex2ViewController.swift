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
    
    private let kBatchSize = 100

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
    
    private var testResults: [RMBTHistoryLoopResult] = []
    private var expandedLoopUuids: [String] = []
    private var nextBatchIndex: Int = 0
    
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
        self.tableView.register(UINib(nibName: RMBTHistoryLoopCell.ID, bundle: nil), forHeaderFooterViewReuseIdentifier: RMBTHistoryLoopCell.ID)
        self.tableView.refreshControl = UIRefreshControl()
        self.tableView.refreshControl?.addTarget(self, action: #selector(refreshFromTableView(_:)), for: .valueChanged)
        if #available(iOS 15.0, *) {
            tableView.sectionHeaderTopPadding = 0
        }
        
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
        
        if let selectedIndexPath = tableView.indexPathForSelectedRow {
            tableView.deselectRow(at: selectedIndexPath, animated: true)
        } else {
            if firstAppearance {
                firstAppearance = false
            }
            if showingLastTestResult {
                // Note: This shouldn't be necessary once we have info required for index view in the
                // test result object. See -displayTestResult.
                showingLastTestResult = false
            }
            loading = true // to avoid duplicate calls to getNextBatch()
            refreshFilters()
        }
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
        
        self.navigationController?.tabBarItem.title = " "
        self.navigationController?.tabBarItem.selectedImage = UIImage(named: "tab_history_selected")
    }
    
    @IBAction func sync(_ sender: Any?) {
        performSegue(withIdentifier: "show_sync_modal", sender: self)
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
            
            let records: [HistoryItem] = response.records
            // We got less results than batch size, this means this was the last batch
            if (records.count < self.kBatchSize) {
                self.nextBatchIndex = NSNotFound
            } else {
                self.nextBatchIndex += 1
            }
            
            var results: [String:[RMBTHistoryResult]] = [:]
            
            for r in records {
                if let result = RMBTHistoryResult(response: r.json()) {
                    if let loopUuid = r.loopUuid {
                        if var _ = results[loopUuid] {
                            results[loopUuid]!.append(result)
                        } else {
                            results[loopUuid] = [result]
                        }
                    } else if let testUuid = r.testUuid {
                        results[testUuid] = [result]
                    }
                }
            }
            
            for (_, loopResults) in results {
                if loopResults.count > 0 {
                    let resultGroup = RMBTHistoryLoopResult(from: loopResults)
                    self.testResults.append(resultGroup)
                    if resultGroup.loopResults.count == 1, let loopUuid = resultGroup.loopUuid {
                        self.expandedLoopUuids.append(loopUuid)
                    }
                }
            }
            self.testResults.sort { $0.timestamp.timeIntervalSince1970 > $1.timestamp.timeIntervalSince1970
            }
            
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
            navigationItem.backBarButtonItem = UIBarButtonItem()
        } else if segue.identifier == "show_sync_modal", let vc = segue.destination as? RMBTHistorySyncModalViewController {
            vc.onSyncSuccess = { [weak self] in
                self?.refresh()
                self?.refreshFilters()
            }
        }
    }
    
}

// MARK: UITableViewDataSource

extension RMBTHistoryIndex2ViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int {
        var result = testResults.count
        if (nextBatchIndex != NSNotFound) { result += 1 }
        return result
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section >= testResults.count {
            return 1
        }
        return testResults[section].loopResults.count
    }
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        guard section < testResults.count, testResults[section].loopResults.count > 1 else {
            return 0
        }
        return 56
    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard section < testResults.count, testResults[section].loopResults.count > 1 else {
            return nil
        }
        let header = tableView.dequeueReusableHeaderFooterView(withIdentifier: RMBTHistoryLoopCell.ID) as! RMBTHistoryLoopCell
        header.dateLabel.text = testResults[section].timeString
        let networkTypeIcon = RMBTNetworkTypeConstants.networkTypeDictionary[testResults[section].networkTypeServerDescription]?.icon
        header.typeImageView.image = networkTypeIcon
        header.onExpand = { [unowned self] in
            self.expandLoopSection(self.testResults[section].loopUuid)
        }
        // header.bottomBorder is hidden by default to avoid border overlapping
        if section < testResults.count - 1 {
            header.bottomBorder.isHidden = true
        }
        return header
    }
    
    private func expandLoopSection(_ loopUuid: String) {
        if let loopUuidIndex = expandedLoopUuids.firstIndex(of: loopUuid) {
            expandedLoopUuids.remove(at: loopUuidIndex)
        } else {
            expandedLoopUuids.append(loopUuid)
        }
        tableView.beginUpdates()
        tableView.endUpdates()
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        guard indexPath.section < testResults.count else {
            return 0
        }
        let section = testResults[indexPath.section]
        if let loopUuid = section.loopUuid, expandedLoopUuids.contains(loopUuid) {
            return 48
        }
        return 0
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if (indexPath.section >= testResults.count) {
            // Loading cell
            let cell = tableView.dequeueReusableCell(withIdentifier: RMBTHistoryLoadingCell.ID, for: indexPath) as! RMBTHistoryLoadingCell
            return cell
        } else {
            let testResult = testResults[indexPath.section].loopResults[indexPath.row]
            
            let cell = tableView.dequeueReusableCell(withIdentifier: RMBTHistoryIndexCell.ID, for: indexPath) as! RMBTHistoryIndexCell

            let networTypeIcon = RMBTNetworkTypeConstants.networkTypeDictionary[testResult.networkTypeServerDescription]?.icon
            cell.typeImageView.image = networTypeIcon
            cell.dateLabel.text = testResult.timeString
            cell.downloadSpeedLabel.text = testResult.downloadSpeedMbpsString
            cell.downloadSpeedIcon.tintColor = .byResultClass(testResult.downloadSpeedClass)
            cell.uploadSpeedLabel.text = testResult.uploadSpeedMbpsString
            cell.uploadSpeedIcon.tintColor = .byResultClass(testResult.uploadSpeedClass)
            cell.pingLabel.text = testResult.shortestPingMillisString
            cell.pingIcon.tintColor = .byResultClass(testResult.pingClass)
            if testResults[indexPath.section].loopResults.count > 1 {
                cell.leftPaddingConstraint?.constant = 32
            } else {
                cell.leftPaddingConstraint?.constant = 20
            }
            // cell.bottomBorder is hidden by default to avoid border overlapping
            if indexPath.section == testResults.count - 1 && indexPath.row == testResults[indexPath.section].loopResults.count - 1 {
                cell.bottomBorder.isHidden = false
            }
            return cell
        }
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard indexPath.section < testResults.count else { return }
        let result = testResults[indexPath.section].loopResults[indexPath.row]
        self.performSegue(withIdentifier: "show_result", sender: result)
    }
    
    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        if indexPath.section >= (testResults.count - 5) {
            if (!loading && nextBatchIndex != NSNotFound) {
                self.getNextBatch()
            }
        }
    }
}

// MARK: Localizations

private extension String {
    static let title = NSLocalizedString("menu_button_history", comment: "History")
}
