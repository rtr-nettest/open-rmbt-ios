//
//  RMBTServerSelectionViewController.swift
//  RMBT
//
//  Copyright © 2026 appscape gmbh. All rights reserved.
//

import UIKit

/// Developer-mode screen for choosing which measurement server the next test should prefer.
///
/// Row 0 is the control-server default (no override); the remaining rows are the servers offered in the
/// `/settings` response (`RMBTSettings.availableTestServers`). The choice is persisted in
/// `RMBTSettings.selectedTestServerUUID` (nil = default) and sent with the test request as `prefer_server`.
///
/// This is a plain dynamic table (not the static Settings table), so the row count can follow the server list
/// without the static-content bounds limitations of `RMBTSettingsViewController`.
final class RMBTServerSelectionViewController: UITableViewController {

    private static let cellReuseIdentifier = "serverCell"

    private let settings = RMBTSettings.shared

    /// Snapshotted once so the list stays stable while the screen is open.
    private let servers: [RMBTMeasurementServer]

    init() {
        self.servers = RMBTSettings.shared.availableTestServers
        super.init(style: .grouped)
    }

    required init?(coder: NSCoder) {
        self.servers = RMBTSettings.shared.availableTestServers
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = NSLocalizedString("preferences_server_selection", comment: "")
        self.tableView.register(UITableViewCell.self, forCellReuseIdentifier: Self.cellReuseIdentifier)
    }

    // MARK: - Table View

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 1 + servers.count // "Default" + one row per offered server
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: Self.cellReuseIdentifier, for: indexPath)

        let title: String
        let isSelected: Bool
        if indexPath.row == 0 {
            title = NSLocalizedString("preferences_default_server_selection", comment: "")
            isSelected = settings.selectedTestServerUUID == nil
        } else {
            let server = servers[indexPath.row - 1]
            title = server.name
            isSelected = settings.selectedTestServerUUID == server.uuid
        }

        var content = cell.defaultContentConfiguration()
        content.text = title
        cell.contentConfiguration = content
        cell.accessoryType = isSelected ? .checkmark : .none
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if indexPath.row == 0 {
            settings.selectedTestServerUUID = nil // control-server default
        } else {
            settings.selectedTestServerUUID = servers[indexPath.row - 1].uuid
        }
        tableView.reloadData() // move the checkmark to the new selection
        tableView.deselectRow(at: indexPath, animated: true)
    }
}
