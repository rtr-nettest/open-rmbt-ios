//
//  RMBTMapResultsListViewController.swift
//  RMBT
//
//  Created by Sergey Glushchenko on 29.08.2021.
//  Copyright © 2021 appscape gmbh. All rights reserved.
//

import UIKit

final class RMBTMapResultsListViewController: UIViewController {

    @IBOutlet weak var collectionView: UICollectionView!
    
    public var onCloseHandler: () -> Void = {}
    public var onDetailsHandler: (_ measurement: SpeedMeasurementResultResponse) -> Void = { _ in }
    public var onChooseHandler: (_ measurement: SpeedMeasurementResultResponse) -> Void = { _ in }
    
    public var measurements: [SpeedMeasurementResultResponse] = [] {
        didSet {
            if self.isViewLoaded {
                self.collectionView.reloadData()
                self.collectionView.setContentOffset(CGPoint.zero, animated: false)
            }
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        collectionView.isPagingEnabled = false
        collectionView.register(UINib(nibName: RMBTMapMeasurementCell.ID, bundle: nil), forCellWithReuseIdentifier: RMBTMapMeasurementCell.ID)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.collectionView.reloadData()
        }
    }
    
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.collectionView.reloadData()
        }
    }
    
    private var targetVelocity: CGPoint = CGPoint()
}

extension RMBTMapResultsListViewController: UICollectionViewDelegate, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return measurements.count
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        return CGSize(width: collectionView.bounds.width - 32, height: 313)
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let measurement = self.measurements[indexPath.row]
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: RMBTMapMeasurementCell.ID, for: indexPath) as! RMBTMapMeasurementCell
        cell.titleLabel.text = measurement.timeString
        if let speed = measurement.result?.download {
            cell.downloadValueLabel.text = RMBTSpeedMbpsString(Double(speed), withMbps: false)
        } else {
            cell.downloadValueLabel.text = "--"
        }
        if let speed = measurement.result?.upload {
            cell.uploadValueLabel.text = RMBTSpeedMbpsString(Double(speed), withMbps: false)
        } else {
            cell.uploadValueLabel.text = "--"
        }
        if let ping = measurement.result?.ping {
            cell.pingValueLabel.text = String(ping)
        } else {
            cell.pingValueLabel.text = "--"
        }
        
        cell.pingImageView.image = .pingIconByResultClass(measurement.result?.pingClassification)
        cell.downloadImageView.image = .downloadIconByResultClass(measurement.result?.downloadClassification)
        cell.uploadImageView.image = .uploadIconByResultClass(measurement.result?.uploadClassification)

        cell.networkDetailList = measurement.networkDetailList ?? []
        
        cell.onCloseHandler = self.onCloseHandler
        cell.onDetailsHandler = { [weak self] in
            self?.onDetailsHandler(measurement)
        }
        return cell
    }
}

extension RMBTMapResultsListViewController: UIScrollViewDelegate {
    func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        targetContentOffset.pointee.x = scrollView.contentOffset.x // Stop animation
        targetVelocity = velocity
    }
    
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        var offset = CGPoint()
        
        var isToLeft = false
        if targetVelocity.x > 0 {
            isToLeft = true
        }
        
        if let pageOffset = ScrollPageController().pageOffset(
            for: scrollView.contentOffset.x + (abs(targetVelocity.x) > 0.5 ? (isToLeft ? 100 : -100) : 0),
            velocity: 0,
            in: pageOffsets(in: scrollView)
        ) {
            offset.x = pageOffset
        }

        scrollView.setContentOffset(offset, animated: true)
        let page = Int(offset.x / scrollView.frame.width)
        guard self.measurements.count > page else { return }
        let measurement = self.measurements[page]
        self.onChooseHandler(measurement)
    }


    private func pageOffsets(in scrollView: UIScrollView) -> [CGFloat] {
        let offsetForScreen = (self.collectionView.bounds.width - 24)
        var offsets: [CGFloat] = []
        for i in 0...5 {
            offsets.append(offsetForScreen * CGFloat(i))
        }
        return offsets
    }
}


struct ScrollPageController {

    /// Computes page offset from page offsets array for given scroll offset and velocity
    ///
    /// - Parameters:
    ///   - offset: current scroll offset
    ///   - velocity: current scroll velocity
    ///   - pageOffsets: page offsets array
    /// - Returns: target page offset from array or nil if no page offets provided
    func pageOffset(for offset: CGFloat, velocity: CGFloat, in pageOffsets: [CGFloat]) -> CGFloat? {
        let pages = pageOffsets.enumerated().reduce([Int: CGFloat]()) {
            var dict = $0
            dict[$1.0] = $1.1
            return dict
        }
        guard let page = pages.min(by: { abs($0.1 - offset) < abs($1.1 - offset) }) else {
            return nil
        }
        if abs(velocity) < 0.2 {
            return page.value
        }
        if velocity < 0 {
            return pages[pageOffsets.index(before: page.key)] ?? page.value
        }
        return pages[pageOffsets.index(after: page.key)] ?? page.value
    }

    /// Cumputes page fraction from page offsets array for given scroll offset
    ///
    /// - Parameters:
    ///   - offset: current scroll offset
    ///   - pageOffsets: page offsets array
    /// - Returns: current page fraction in range from 0 to number of pages or nil if no page offets provided
    func pageFraction(for offset: CGFloat, in pageOffsets: [CGFloat]) -> CGFloat? {
        let pages = pageOffsets.sorted().enumerated()
        if let index = pages.first(where: { $0.1 == offset })?.0 {
            return CGFloat(index)
        }
        guard let nextOffset = pages.first(where: { $0.1 >= offset })?.1 else {
            return pages.map { $0.0 }.last.map { CGFloat($0) }
        }
        guard let (prevIdx, prevOffset) = pages.reversed().first(where: { $0.1 <= offset }) else {
            return pages.map { $0.0 }.first.map { CGFloat($0) }
        }
        return CGFloat(prevIdx) + (offset - prevOffset) / (nextOffset - prevOffset)
    }

}
