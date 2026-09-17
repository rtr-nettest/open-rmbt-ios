//
//  RMBTMapOptionsTypes2ViewController.swift
//  RMBT
//
//  Created by Sergey Glushchenko on 25.08.2021.
//  Copyright © 2021 appscape gmbh. All rights reserved.
//

import UIKit

class RMBTMapOptionsTypesViewController: UIViewController {

    @IBOutlet weak var confirmButton: UIButton!
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var tableView: UITableView!
    
    var filter: RMBTMapOptionsFilter?
    var onMapTypeChange: ((RMBTMapOptionsFilter?) -> Void)?
    
    override func viewDidLoad() {
        super.viewDidLoad()

        self.navigationItem.title = NSLocalizedString("Map type", comment: "Title of the map options subview")
        
        self.confirmButton.setTitle(.accept, for: .normal)
        
        self.tableView.register(UINib(nibName: RMBTMapOptionsTypeCell.ID, bundle: nil), forCellReuseIdentifier: RMBTMapOptionsTypeCell.ID)
        
        self.tableView.tintColor = .brand
    }
    
    @IBAction func confirmButtonClick(_ sender: Any) {
        self.onMapTypeChange?(self.filter)
        self.navigationController?.popViewController(animated: true)
    }
}

extension RMBTMapOptionsTypesViewController: UITableViewDelegate, UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return filter?.possibleValues.count ?? 0
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return filter?.possibleValues[section].options?.count ?? 0
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 48
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let subtype = filter?.possibleValues[indexPath.section].options?[indexPath.row]
        
        let cell = tableView.dequeueReusableCell(withIdentifier: RMBTMapOptionsTypeCell.ID, for: indexPath) as! RMBTMapOptionsTypeCell
        
        cell.titleLabel.text = subtype?.title
        cell.subtitleLabel.text = subtype?.summary
     
        cell.accessoryType = self.filter?.activeValue?.activeOption == subtype ? .checkmark : .none
        return cell
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return self.filter?.possibleValues[section].title
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let type = filter?.possibleValues[indexPath.section]
        type?.activeOption = filter?.possibleValues[indexPath.section].options?[indexPath.row]
        self.filter?.activeValue = type
        self.tableView.reloadData()
    }
}

extension RMBTMapOptionsTypesViewController: RMBTBottomCardProtocol {
    var contentSize: CGSize { return CGSize(width: 0, height: 600) }
}

private extension String {
    static let accept = NSLocalizedString("button_accept.title", comment: "")
}
