//
//  RMBTHistoryQoSSingleViewController.swift
//  RMBT
//
//  Created by Sergey Glushchenko on 11.09.2021.
//  Copyright © 2021 appscape gmbh. All rights reserved.
//

import UIKit
import MaterialComponents.MaterialTabs_TabBarView

final class RMBTHistoryQoSSingleViewController: UIViewController {

    @IBOutlet private weak var tableView: UITableView!
    
    public var result: RMBTHistoryQoSSingleResult?
    public var groupResult: RMBTHistoryQoSGroupResult?
    public var seqNumber: UInt = 0
    
    private lazy var mdcTabBarView: MDCTabBarView? = {
        if let results = groupResult?.tests {
            let mdcTabBarView = MDCTabBarView()
            mdcTabBarView.setContentPadding(UIEdgeInsets(top: 10, left: 0, bottom: 0, right: 0), for: .scrollable)
            mdcTabBarView.items = results.enumerated().map({ (index, item) in
                return UITabBarItem(title: "#\(index+1)", image: nil, tag: item.uid as! Int)
            })
            mdcTabBarView.selectedItem = mdcTabBarView.items[Int(seqNumber) - 1]
            mdcTabBarView.preferredLayoutStyle = .scrollable // or .fixed
            mdcTabBarView.tabBarDelegate = self
            mdcTabBarView.selectionIndicatorStrokeColor = .brand
            mdcTabBarView.rippleColor = mdcTabBarView.selectionIndicatorStrokeColor?.withAlphaComponent(0.1) ?? .clear
            mdcTabBarView.setTitleFont(UIFont.roboto(size: 14, weight: .regular), for: .normal)
            return mdcTabBarView
        }
        return nil
    }()

    override func viewDidLoad() {
        super.viewDidLoad()

        self.title = groupResult?.name
        
        self.tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        self.tableView.estimatedRowHeight = 140.0;
        self.tableView.rowHeight = UITableView.automaticDimension
        self.tableView.tableFooterView = UIView()
        self.tableView.tableHeaderView = UIView()
        if #available(iOS 15.0, *) {
            self.tableView.sectionHeaderTopPadding = 0
        }

        self.tableView.register(UINib(nibName: RMBTHistoryQoSGroupResultCell.ID, bundle: nil), forCellReuseIdentifier: RMBTHistoryQoSGroupResultCell.ID)
        self.tableView.register(UINib(nibName: RMBTHistoryQoSTitledResultCell.ID, bundle: nil), forCellReuseIdentifier: RMBTHistoryQoSTitledResultCell.ID)
    }
    
    private func titleForSection(section: Int) -> String? {
        if (section == 0) {
            return NSLocalizedString("Description", comment: "").uppercased();
        } else if (section == 1) {
            return NSLocalizedString("Details", comment: "Section header").uppercased();
        } else {
            return nil
        }
    }
}

extension RMBTHistoryQoSSingleViewController: UITableViewDelegate, UITableViewDataSource {
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return 2
    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        return section == 0 ? mdcTabBarView : nil
    }
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return section == 0 && mdcTabBarView != nil ? 48 : 0
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == 0 {
            return 1
        } else {
            return 1
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if (indexPath.section == 0) {
            let descriptionCell = tableView.dequeueReusableCell(withIdentifier: RMBTHistoryQoSGroupResultCell.ID, for: indexPath) as! RMBTHistoryQoSGroupResultCell
            descriptionCell.titleLabel.text = self.titleForSection(section: indexPath.section)
            descriptionCell.descriptionLabel.text = self.result?.summary
            descriptionCell.result = self.result
            return descriptionCell
        } else {
            let descriptionCell = tableView.dequeueReusableCell(withIdentifier: RMBTHistoryQoSTitledResultCell.ID, for: indexPath) as! RMBTHistoryQoSTitledResultCell
            descriptionCell.titleLabel.text = self.titleForSection(section: indexPath.section)
            descriptionCell.descriptionLabel.text = self.result?.details
            return descriptionCell
        }
    }
}

extension RMBTHistoryQoSSingleViewController: MDCTabBarViewDelegate {
    func tabBarView(_ tabBarView: MDCTabBarView, didSelect item: UITabBarItem) {
        guard let results = groupResult?.tests else { return }
        result = results.first(where: { res in
            res.uid as! Int == item.tag
        })
        tableView.reloadData()
    }
}
