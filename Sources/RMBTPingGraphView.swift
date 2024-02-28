//
//  RMBTPingGraphView.swift
//  RMBT
//
//  Created by Sergey Glushchenko on 10.11.2021.
//  Copyright © 2021 appscape gmbh. All rights reserved.
//

import Foundation
import UIKit

private final class RMBTVerticalAxisView: UIView {
    public var gapsCount: Int = 5 {
        didSet {
            recreateGaps()
            self.setNeedsLayout()
        }
    }
    
    public var minValue: CGFloat = 0 {
        didSet {
            self.setNeedsLayout()
        }
    }
    
    public var maxValue: CGFloat = 10 {
        didSet {
            _ = getYLabels()
            self.setNeedsLayout()
        }
    }
    
    public var maxAxisValue: CGFloat = 10
    
    //Calculate gaps and set maximum value that will be showed
    private func getYLabels() -> [Int] {

        let gap = Int(ceil((Double(maxValue * Double(gapsCount)) / 100.0) * Double(gapsCount)))
        var gaps: [Int] = []
        
        for i in 0..<gapsCount {
            gaps.append(i * gap)
        }
        
        maxAxisValue = CGFloat(gaps.last ?? Int(maxValue))
        return gaps.reversed()
    }
    
    public var labelsColor: UIColor = UIColor.rmbt_color(withRGBHex: 0xFFFFFF, alpha: 0.56) {
        didSet {
            for label in labels {
                label.textColor = labelsColor
            }
        }
    }
    
    private var labels: [UILabel] = []
    
    //Create labels
    func recreateGaps() {
        labels.forEach({ $0.removeFromSuperview() })
        var labels: [UILabel] = []
        for _ in 0..<gapsCount {
            let label = RMBTGraphLabel(text: "1", textColor: labelsColor)
            labels.append(label)
            self.addSubview(label)
        }
        self.labels = labels
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        recreateGaps()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        //Update positions for gaps
        let height = self.frame.size.height + CGFloat(2 * gapsCount)
        let offset = ceil(height / CGFloat(gapsCount))
        let gaps = self.getYLabels()
        for (index, label) in labels.enumerated() {
            label.frame.origin.y = offset * CGFloat(index)
            label.frame.origin.x = 0
            label.frame.size = CGSize(width: self.frame.width, height: label.font.pointSize)
            label.text = String(gaps[index]) + " ms"
        }
    }
}

final private class RMBTPingContentGraphView: UIView {
    var values: [CGPoint] = []
    
    public var minValue: CGFloat = 0 {
        didSet {
            self.setNeedsDisplay()
        }
    }
    
    public var maxValue: CGFloat = 10 {
        didSet {
            self.setNeedsDisplay()
        }
    }
    
    public var maxXValue: CGFloat = 0
    public var minXValue: CGFloat = 0
    
    public var columnColor: UIColor = UIColor.rmbt_color(withRGBHex:0x78ED03).withAlphaComponent(0.3) {
        didSet {
            self.setNeedsDisplay()
        }
    }

    public var showBarChart: Bool = false {
        didSet {
            self.setNeedsDisplay()
        }
    }

    override func draw(_ rect: CGRect) {
        let context = UIGraphicsGetCurrentContext()
        context?.translateBy(x: 0, y: self.bounds.size.height)
        context?.scaleBy(x: 1.0, y: -1.0)

        let minX = values.min(by: { $0.x < $1.x })
        let maxX = values.max(by: { $0.x < $1.x })
        
        self.minXValue = minX?.x ?? 0
        self.maxXValue = maxX?.x ?? 0.1
        
//        if maxX - minX > 1.0 * TimeInterval(NSEC_PER_SEC) {
//            let duration = maxX - minX
//            maxXValue = secondWidth / duration * self.frameWidth
//        } else {
//            maxXValue = self.frameWidth
//        }
//        maxXValue = CGFloat(values.count * 20 + 15 + 15)
//        if maxXValue > self.frameWidth {
//            maxXValue = self.frameWidth
//        }
        
//        let count = 10
//        var values: [CGFloat] = []
//        if self.values.count > count {
//            let step = CGFloat(self.values.count) / CGFloat(count)
//            for index in 0..<count {
//                let startIndex = Int(CGFloat(index) * step)
//                let endIndex = Int(CGFloat(index + 1) * step)
//                var value = 0.0
//                var countItems = 0
//                for i in startIndex..<endIndex {
//                    if self.values.count > i {
//                        value += self.values[i]
//                        countItems += 1
//                    }
//                }
//                if countItems > 0 {
//                    values.append(CGFloat(value) / CGFloat(countItems))
//                }
//            }
//        } else {
//            values = self.values
//        }
        
        
//        for (index, value) in values.enumerated() {
//            let bezier = self.column(with: value, at: index, totalCount: values.count)
//            context?.addPath(bezier.cgPath)
//        }
        
        guard values.count > 0 else { return }

        if showBarChart {
            for (index, value) in values.enumerated() {
                let bezier = self.column(with: value.y, at: index, totalCount: values.count)
                context?.addPath(bezier.cgPath)
            }
        } else {
            context?.addPath(self.line().cgPath)
        }

        context?.setFillColor(columnColor.cgColor)
        context?.fillPath()
    }
    
    func convertXValueToCoordinate(_ value: CGFloat) -> CGFloat {
        let secondWidth = self.frameWidth
        var width = 0.0
        var duration = maxXValue - minXValue
        if duration > 1.0 * TimeInterval(NSEC_PER_SEC) {
            width = secondWidth * duration / TimeInterval(NSEC_PER_SEC)
        } else {
            width = self.frameWidth
            duration = 1.0 * TimeInterval(NSEC_PER_SEC)
        }
        width = self.frameWidth

        return (value - minXValue) * width / duration
    }
    
    func line() -> UIBezierPath {
        let pathStroke = UIBezierPath()
        var lX: CGFloat = 0
        var lY: CGFloat = 0
      
        let heightSegment: CGFloat = self.frameHeight / self.maxValue
        
        pathStroke.move(to: CGPoint(x: 0, y: 0))
        pathStroke.addLine(to: CGPoint(x: 0, y: heightSegment * values[0].y))
        
        for index in 1..<values.count {
            let value = values[index]
            let currentPointX = self.convertXValueToCoordinate(value.x)
            let currentPointY = (values[index].y * heightSegment)
            
            let prevValue = values[index-1]
            let previousPointX = self.convertXValueToCoordinate(prevValue.x)
            let previousPointY = (values[index - 1].y * heightSegment)
            
            // Distance between currentPoint and previousPoint
            let firstDistance = sqrt(pow(currentPointX - previousPointX, 2.0) + pow(currentPointY - previousPointY, 2.0))
            
            // Minimum is used to avoid going too much right
            let firstX = min(previousPointX + lX * firstDistance, (previousPointX + currentPointX) / 2)
            let firstY = previousPointY + lY * firstDistance

            let nextValue = values[index + 1 < values.count ? index + 1 : index]
            let nextPointX = convertXValueToCoordinate(nextValue.x)
            let nextPointY = (values[(index + 1 < values.count) ? index + 1 : index].y * heightSegment)
            
            // Distance between nextPoint and previousPoint (length of reference line)
            let secondDistance = sqrt(pow(nextPointX - previousPointX, 2.0) + pow(nextPointY - previousPointY, 2.0))
            // (lX,lY) is the slope of the reference line
            lX = (nextPointX - previousPointX) / secondDistance * 0.3
            lY = (nextPointY - previousPointY) / secondDistance * 0.3
            
            // Maximum is used to avoid going too much left
            let secondX = max(currentPointX - lX * firstDistance, (previousPointX + currentPointX) / 2)
            let secondY = currentPointY - lY * firstDistance

            pathStroke.addCurve(to: CGPoint(x: currentPointX, y: currentPointY),
                                controlPoint1: CGPoint(x: firstX, y: firstY),
                                controlPoint2: CGPoint(x: secondX, y: secondY))
        }
        
        var lastPoint = pathStroke.currentPoint
        lastPoint.y = 0
        pathStroke.addLine(to: lastPoint)
        
        return pathStroke
    }
    
    // Create path for drawing value
    func column(with value: CGFloat, at index: Int, totalCount: Int) -> UIBezierPath {
        let offset = 2.0
        var width = (Double(self.frame.width) - (offset * Double(totalCount))) / Double(totalCount)
        if width > 20 {
            width = 20
        }
        let maxHeight = self.frame.height
        let height = maxHeight * Double(value) / Double(maxValue)
        
        let x = offset / 2 + (offset + width) * Double(index)
        let bezier = UIBezierPath(rect: CGRect(x: x, y: 0, width: width, height: height))
        return bezier
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        self.backgroundColor = UIColor.clear
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@objc final class RMBTPingGraphView: UIView {
    private static let RMBTSpeedGraphViewSeconds: TimeInterval = 8.0
    
    private static let contentFrame: CGRect = CGRect(x: 34.5, y: 32.5, width: 243.0,  height: 92.0)
    private lazy var axiesView: RMBTVerticalAxisView = {
        let view = RMBTVerticalAxisView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private lazy var contentView: RMBTPingContentGraphView = {
        let view = RMBTPingContentGraphView()
        view.showBarChart = self.showBarChart
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private lazy var secondsLabel: UILabel = {
        let label = RMBTGraphLabel(text: "1s", textColor: labelsColor)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private var backgroundImage: UIImage?

    private var backgroundLayer: CALayer = CALayer()

    private let bottomOffset: CGFloat = 20
    private var graphRect: CGRect {
        var rect = self.bounds
        rect.size.width -= 40
        rect.size.height -= bottomOffset
        return rect
    }
    
    fileprivate var chartPoints: [CGPoint] = [] {
        didSet {
            let maxValue = chartPoints.max(by: { $0.y < $1.y })?.y ?? 0.0
            let minValue = 0.0
            axiesView.minValue = minValue
            axiesView.maxValue = maxValue
            
            contentView.minValue = minValue
            // use maxAxisValue for correct scale
            contentView.maxValue = axiesView.maxAxisValue
            
            contentView.values = chartPoints
            
            let minXValue = chartPoints.min(by: { $0.x < $1.x })?.x ?? 0.0
            let maxXValue = chartPoints.max(by: { $0.x < $1.x })?.x ?? 0.0
            let duration = TimeInterval(maxXValue - minXValue) / TimeInterval(NSEC_PER_SEC)
            secondsLabel.text = String(format: "%0.0fs", ceil(duration) == 0 ? 1.0 : ceil(duration))
        }
    }
    
    public var labelsColor: UIColor = UIColor.rmbt_color(withRGBHex: 0xFFFFFF, alpha: 0.56) {
        didSet {
            self.axiesView.labelsColor = labelsColor
            updateUI()
        }
    }
    public var graphLinesColor: UIColor = UIColor.rmbt_color(withRGBHex: 0x3D3D3D, alpha: 1.0) {
        didSet {
            updateUI()
        }
    }
    
    public var lineColor: UIColor = UIColor.rmbt_color(withRGBHex:0x78ED03) {
        didSet {
            contentView.columnColor = lineColor.withAlphaComponent(0.3)
        }
    }

    public var showBarChart: Bool = false {
        didSet {
            contentView.showBarChart = showBarChart
        }
    }

    @objc public func add(value: CGFloat, at timeInterval: TimeInterval) {
        let p = CGPoint(x: timeInterval, y: value)
        var chartPoints = self.chartPoints
        chartPoints.append(p)
        self.chartPoints = chartPoints
    }
    
    @objc public func clear() {
        chartPoints = []
    }
    
    private func setup() {
        self.backgroundColor = UIColor.clear
        self.backgroundImage = self.markedBackgroundImage()
    
        backgroundLayer.frame = self.graphRect
        backgroundLayer.contents = backgroundImage?.cgImage
        
        self.layer.addSublayer(backgroundLayer)

        updateUI()
        
        self.addSubview(axiesView)
        NSLayoutConstraint.activate([
            axiesView.rightAnchor.constraint(equalTo: self.rightAnchor, constant: 0),
            axiesView.topAnchor.constraint(equalTo: self.topAnchor, constant: 0),
            axiesView.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: -bottomOffset),
            axiesView.widthAnchor.constraint(equalToConstant: 40)
        ])
        
        self.addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.leftAnchor.constraint(equalTo: self.leftAnchor, constant: 0),
            contentView.topAnchor.constraint(equalTo: self.topAnchor, constant: 0),
            contentView.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: -bottomOffset),
            contentView.rightAnchor.constraint(equalTo: self.axiesView.leftAnchor, constant: 0)
        ])
        
        self.addSubview(secondsLabel)
        NSLayoutConstraint.activate([
            secondsLabel.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: 0),
            secondsLabel.rightAnchor.constraint(equalTo: self.axiesView.leftAnchor, constant: 0)
        ])
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        self.setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
        self.setup()
    }
    
    override var intrinsicContentSize: CGSize {
        return backgroundImage?.size ?? CGSize()
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        backgroundLayer.frame = self.graphRect
        updateUI()
    }
    
    func updateUI() {
        self.backgroundImage = self.markedBackgroundImage()
        backgroundLayer.contents = backgroundImage?.cgImage
    }
    
    // Create background image
    private func markedBackgroundImage() -> UIImage? {
        let size = self.graphRect.size
        UIGraphicsBeginImageContextWithOptions(size, false, 0.0 /* device main screen*/);
        let context = UIGraphicsGetCurrentContext();

        context?.setLineWidth(1 / UIScreen.main.scale)
        context?.setStrokeColor(graphLinesColor.cgColor)
        let countLines = 4
        let offset = size.height / CGFloat(countLines)
        for i in 0..<countLines + 1 {
            context?.move(to: CGPoint(x: 0, y: size.height - offset * CGFloat(i)))
            context?.addLine(to: CGPoint(x: size.width, y: size.height - offset * CGFloat(i)))
        }
        
        context?.strokePath()
        
        context?.move(to: CGPoint(x: size.width, y: size.height))
        context?.addLine(to: CGPoint(x: size.width, y: 0))
        context?.setLineDash(phase: 0.0, lengths: [2, 3])
        context?.strokePath()
        
        let markedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext();
    
        return markedImage
    }
}
