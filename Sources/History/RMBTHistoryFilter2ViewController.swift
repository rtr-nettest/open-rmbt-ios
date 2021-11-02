//
//  RMBTHistoryFilter2ViewController.swift
//  RMBT
//
//  Created by Sergey Glushchenko on 06.09.2021.
//  Copyright © 2021 appscape gmbh. All rights reserved.
//

import Foundation

final class RMBTHistoryFilter2ViewController: UIViewController {
    
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var tableView: UITableView!
    
    var onFilterChanged: (_ activeFilters: [String: [String]]) -> Void = { _ in }
    
    var allFilters: [String: [String]] = [:] {
        didSet {
            self.keys = Array(allFilters.keys)
        }
    }
    var activeFilters: [String: [String]] = [:]
    
    private var keys: [String] = []
    
    private var activeIndexPaths: Set<IndexPath> = []
    private var allIndexPaths: Set<IndexPath> = []

    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.navigationController?.delegate = self
        
        tableView.register(UINib(nibName: RMBTHistoryFilterTitleCell.ID, bundle: nil), forCellReuseIdentifier: RMBTHistoryFilterTitleCell.ID)
        tableView.tableFooterView = UIView()
    }
    
    @IBAction func closeButtonClick(_ sender: Any) {
        self.onFilterChanged(self.activeFilters)
        self.dismiss(animated: true, completion: nil)
    }
    
    func icon(for key: String) -> UIImage? {
        if key == "networks" {
            return UIImage(named: "filters_networks_icon")
        } else if key == "devices" {
            return UIImage(named: "filters_devices_icon")
        }
        
        return nil
    }
    
    func title(for key: String) -> String {
        if key == "networks" {
            return NSLocalizedString("Network Type", comment: "Filter section title")
        } else if key == "devices" {
            return NSLocalizedString("Device", comment: "Filter section title")
        } 
        return key
    }
    
    func value(for key: String) -> String? {
        let filters = activeFilters[key]
        return filters?.joined(separator: ", ")
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        guard let indexPath = sender as? IndexPath else { return }

        if segue.identifier == "show_filters",
           let vc = segue.destination as? RMBTHistoryFiltersOptionsViewController {
            let key = keys[indexPath.row]
            let filters = self.allFilters[key]
            vc.allFilters = filters ?? []
            vc.activeFilters = activeFilters[key] ?? []
            vc.title = self.title(for: key)
            vc.key = key
            vc.onComplete = { [weak self] key, filters in
                guard let self = self else { return }
                self.activeFilters[key] = filters.count == 0 ? self.allFilters[key] : filters
                self.onFilterChanged(self.activeFilters)
                self.tableView.reloadData()
            }
        }
    }
}

extension RMBTHistoryFilter2ViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.allFilters.keys.count
    }
   
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 48
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: RMBTHistoryFilterTitleCell.ID, for: indexPath) as! RMBTHistoryFilterTitleCell
        let key = Array(self.allFilters.keys)[indexPath.row]
        cell.titleLabel?.text = self.title(for: key)
        cell.valueLabel?.text = self.value(for: key)
        cell.iconImageView.image = self.icon(for: key)
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        self.performSegue(withIdentifier: "show_filters", sender: indexPath)
    }

}

extension RMBTHistoryFilter2ViewController: RMBTBottomCardProtocol {
    var contentSize: CGSize { return CGSize(width: 0, height: 302) }
}

extension RMBTHistoryFilter2ViewController: UINavigationControllerDelegate {
    func navigationController(_ navigationController: UINavigationController, animationControllerFor operation: UINavigationController.Operation, from fromVC: UIViewController, to toVC: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        switch operation {
        case .push: return PushAnimator()
        case .pop: return PopAnimator()
        default: break
        }
        return nil
    }
}
