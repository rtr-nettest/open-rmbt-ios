//
//  RMBTHistoryPingGraphCell.swift
//  RMBT
//
//  Created by Sergey Glushchenko on 09.09.2021.
//  Copyright © 2021 appscape gmbh. All rights reserved.
//

import UIKit

final class RMBTHistoryPingGraphCell: UICollectionViewCell {

    static let ID = "RMBTHistoryPingGraphCell"
    
    @IBOutlet weak var pingGraphView: RMBTPingGraphView! {
        didSet {
            pingGraphView.labelsColor = UIColor.rmbt_color(withRGBHex: 0x424242, alpha: 0.56)
            pingGraphView.graphLinesColor = UIColor.rmbt_color(withRGBHex: 0xEEEEEE, alpha: 1.0)
        }
    }
    
    var graph: RMBTHistoryPingGraph? {
        didSet {
            if let graph = graph {
                pingGraphView.clear()
                for p in graph.pings {
                    pingGraphView.add(value: p.pingMs, at: Double(p.timeElapsed) * 1.0e+6)
                }
                
                self.pingGraphView.isHidden = false
            } else {
                self.pingGraphView.isHidden = true
            }
        }
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
        
        pingGraphView.clear()
        pingGraphView.showBarChart = true
    }

}
