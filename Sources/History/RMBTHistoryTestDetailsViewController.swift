//
//  RMBTHistoryTestDetailsViewController.swift
//  RMBT
//
//  Created by Polina Gurina on 25.11.2021.
//  Copyright © 2021 appscape gmbh. All rights reserved.
//

import UIKit

class RMBTHistoryTestDetailsViewController: UITableViewController {
    var testDetails: [RMBTHistoryResultItem] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(UINib(nibName: RMBTTestDetailCell.ID, bundle: nil), forCellReuseIdentifier: RMBTTestDetailCell.ID)
        tableView.separatorInset = .init(top: 0, left: 20, bottom: 0, right: 20)
        tableView.tableHeaderView = UIView()
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return testDetails.count
    }
    
    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 60
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: RMBTTestDetailCell.ID, for: indexPath) as! RMBTTestDetailCell
        if indexPath.row < testDetails.count {
            cell.titleLabel.text = testDetails[indexPath.row].title
            cell.valueLabel.text = testDetails[indexPath.row].value
        }
        cell.selectionStyle = .none
        return cell
    }
}
