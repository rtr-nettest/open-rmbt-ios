//
//  RMBTMapOptionsViewController.swift
//  RMBT
//
//  Created by Sergey Glushchenko on 19.08.2021.
//  Copyright © 2021 appscape gmbh. All rights reserved.
//

import UIKit

protocol RMBTMapOptionsViewControllerDelegate: AnyObject {
    func mapOptionsViewController(_ vc: RMBTMapOptionsViewController, willDisappearWithChange isChange: Bool)
}

final class RMBTMapOptionsViewController: UIViewController {

    @IBOutlet weak var closeButton: UIButton!
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var tableView: UITableView!
    
    private var lastSelection: IndexPath?
    
    private var activeFiltersAtStart: [RMBTMapOptionsFilterValue]?
    private var activeOverlayAtStart: RMBTMapOptionsOverlay?
    
    var constraint: NSLayoutConstraint?
    
    weak var delegate: RMBTMapOptionsViewControllerDelegate?
    
    var mapOptions: RMBTMapOptions?
    var mapFilters: [RMBTMapOptionsFilter]? {
        return mapOptions?.mapFilters.filter { mapOptions?.isFilterActiveForCurrentContext($0) ?? true }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.register(UINib(nibName: RMBTMapOptionsCell.ID, bundle: nil), forCellReuseIdentifier: RMBTMapOptionsCell.ID)
        
        self.navigationController?.delegate = self
        
        self.activeFiltersAtStart = self.activeFilters()
        self.activeOverlayAtStart = self.mapOptions?.oldActiveOverlay
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        self.tableView.reloadData()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        let change = (activeOverlayAtStart != self.mapOptions?.oldActiveOverlay) ||
            (self.activeFilters() != activeFiltersAtStart)

        self.delegate?.mapOptionsViewController(self, willDisappearWithChange: change)
    }
    
    @IBAction func closeButtonClick(_ sender: Any) {
        self.dismiss(animated: true, completion: nil)
    }
    
    @objc func backButtonClick(_ sender: Any) {
        self.performSegue(withIdentifier: "presentOptions", sender: self)
    }
 
    private func update(_ cell: RMBTMapOptionsCell, at indexPath: IndexPath) {
            let f = self.filter(at: indexPath.row)
            cell.titleLabel?.text = f?.title
            cell.valueLabel?.text = f?.activeValueTitle
            cell.iconImageView.image = f?.icon
    }
    
    private func filter(at index: Int) -> RMBTMapOptionsFilter? {
        return self.mapFilters?[index]
    }
    
    private func activeFilters() -> [RMBTMapOptionsFilterValue]? {
        return self.mapFilters?.compactMap({ $0.activeValue?.activeOption ?? $0.activeValue })
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        let indexPath = sender as? IndexPath
        
        lastSelection = indexPath

        if segue.identifier == "show_filter",
           let vc = segue.destination as? RMBTMapOptionsFilterViewController {
            let filter = self.filter(at: indexPath?.row ?? 0)
            vc.filter = filter
        } else if segue.identifier == "show_types",
           let vc = segue.destination as? RMBTMapOptionsTypesViewController {
            let filter = self.filter(at: indexPath?.row ?? 0)
            vc.filter = filter
            vc.onMapTypeChange = { _ in
                self.mapOptions?.mapFilters.forEach({ filter in
                    if filter.iconValue == "MAP_FILTER_CARRIER" || filter.iconValue == "MAP_FILTER_TECHNOLOGY" {
                        filter.activeValue = filter.possibleValues.first(where: { $0.isDefault })
                    }
                })
            }
        }
    }
}

extension RMBTMapOptionsViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.mapFilters?.count ?? 0
    }
   
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 48
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: RMBTMapOptionsCell.ID, for: indexPath) as! RMBTMapOptionsCell
        self.update(cell, at: indexPath)
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let filter = self.filter(at: indexPath.row)
        if (filter?.iconValue == "MAP_TYPE") {
            self.performSegue(withIdentifier: "show_types", sender: indexPath)
        } else {
            lastSelection = indexPath
            self.performSegue(withIdentifier: "show_filter", sender: indexPath)
        }
    }

}

extension RMBTMapOptionsViewController: RMBTBottomCardProtocol {
    var contentSize: CGSize { return CGSize(width: 0, height: 400) }
}

extension RMBTMapOptionsViewController: UINavigationControllerDelegate {
    func navigationController(_ navigationController: UINavigationController, animationControllerFor operation: UINavigationController.Operation, from fromVC: UIViewController, to toVC: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        switch operation {
        case .push: return PushAnimator()
        case .pop: return PopAnimator()
        default: break
        }
        return nil
    }
}
