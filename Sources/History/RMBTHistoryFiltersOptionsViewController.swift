//
//  RMBTHistoryFiltersOptionsViewController.swift
//  RMBT
//
//  Created by Sergey Glushchenko on 25.08.2021.
//  Copyright © 2021 appscape gmbh. All rights reserved.
//

import UIKit

class RMBTHistoryFiltersOptionsViewController: UIViewController {

    @IBOutlet weak var confirmButton: UIButton!
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var tableView: UITableView!
    
    var onComplete: (_ key: String, _ activeFilter: [String]) -> Void = { _, _ in }
    
    var allFilters: [String] = []
    var activeFilters: [String] = []
    var key: String = ""
    
    override func viewDidLoad() {
        super.viewDidLoad()

        self.confirmButton.setTitle(.accept, for: .normal)
        self.titleLabel.text = self.title
        
        self.tableView.register(UINib(nibName: RMBTMapOptionsTypeCell.ID, bundle: nil), forCellReuseIdentifier: RMBTMapOptionsTypeCell.ID)
        
        self.tableView.tintColor = .brand
        
        // Add long tap gesture recognizer to table view. On long tap, select tapped filter, while deselecting
        // all other filters from that group.
        let longPressGestureRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(tableViewDidReceiveLongPress(_:)))
        longPressGestureRecognizer.minimumPressDuration = 0.8
        self.tableView.addGestureRecognizer(longPressGestureRecognizer)
    }
    
    @IBAction func confirmButtonClick(_ sender: Any) {
        self.onComplete(key, activeFilters)
        self.navigationController?.popViewController(animated: true)
    }
    
    @objc func tableViewDidReceiveLongPress(_ gestureRecognizer: UIGestureRecognizer) {
        if gestureRecognizer.state == .began {
            let p = gestureRecognizer.location(in: self.tableView)
            guard let tappedIndexPath = self.tableView.indexPathForRow(at: p) else { return }
            
            self.activeFilters = []
            self.activeFilters.append(self.allFilters[tappedIndexPath.row])
            self.tableView.reloadData()
        }
    }
}

extension RMBTHistoryFiltersOptionsViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return allFilters.count
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 48
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: RMBTMapOptionsTypeCell.ID, for: indexPath) as! RMBTMapOptionsTypeCell
        
        let value = allFilters[indexPath.row]
        cell.titleLabel.text = value
        cell.subtitleLabel.text = nil
     
        cell.accessoryType = activeFilters.contains(value) ? .checkmark : .none
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let value = allFilters[indexPath.row]
        if let index = activeFilters.firstIndex(of: value) {
            activeFilters.remove(at: index)
        } else {
            activeFilters.append(value)
        }
        self.tableView.reloadData()
    }
}

extension RMBTHistoryFiltersOptionsViewController: RMBTBottomCardProtocol {
    var contentSize: CGSize {
        var height = allFilters.count * 48 + 106 + 148
        if height > 500 {
            height = 500
        }
        return CGSize(width: 0, height: height) }
}

private extension String {
    static let accept = NSLocalizedString("button_accept.title", comment: "")
}
