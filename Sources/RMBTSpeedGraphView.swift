//
//  RMBTSpeedGraphView.swift
//  RMBT
//
//  Created by Sergey Glushchenko on 10.11.2021.
//  Copyright © 2021 appscape gmbh. All rights reserved.
//

import Foundation
import UIKit

@objc class RMBTSpeedGraphView: UIView {
    private let labelHeight = CGFloat(11)
    private let labelWidth = CGFloat(30)

    private static let RMBTSpeedGraphViewContentFrame: CGRect = CGRect(x: 34.5, y: 32.5, width: 243.0,  height: 92.0)
    private static let RMBTSpeedGraphViewSeconds: TimeInterval = 8.0
    
    private var backgroundImage: UIImage?
    
    internal private(set) var widthPerSecond: CGFloat = 0.0

    private var backgroundLayer: CALayer = CALayer()
    private var linesLayer: CAShapeLayer = CAShapeLayer()
    private var fillLayer: CAShapeLayer = CAShapeLayer()
    
    internal var graphRect: CGRect {
        var rect = self.bounds
        rect.size.width -= labelWidth + 5
        rect.size.height -= 18
        return rect
    }
    
    fileprivate var chartPoints: [CGPoint] = []
    
    private var value1TopConstraint: NSLayoutConstraint?
    private lazy var value1Label: UILabel = {
        let label = RMBTGraphLabel(text: "1", textColor: labelsColor)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private var value10TopConstraint: NSLayoutConstraint?
    private lazy var value10Label: UILabel = {
        let label = RMBTGraphLabel(text: "10", textColor: labelsColor)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private var value100TopConstraint: NSLayoutConstraint?
    private lazy var value100Label: UILabel = {
        let label = RMBTGraphLabel(text: "100", textColor: labelsColor)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private var value1000TopConstraint: NSLayoutConstraint?
    private lazy var value1000Label: UILabel = {
        let label = RMBTGraphLabel(text: "1G", textColor: labelsColor)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private var value10000TopConstraint: NSLayoutConstraint?
    private lazy var value10000Label: UILabel = {
        let label = RMBTGraphLabel(text: "10G", textColor: labelsColor)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    
    private lazy var startIntervalLabel: UILabel = {
        let label = RMBTGraphLabel(text: "0s", textColor: labelsColor)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private lazy var endIntervalLabel: UILabel = {
        let label = RMBTGraphLabel(text: "8s", textColor: labelsColor)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    public var labelsColor: UIColor = UIColor.rmbt_color(withRGBHex: 0xFFFFFF, alpha: 0.56) {
        didSet {
            startIntervalLabel.textColor = labelsColor
            endIntervalLabel.textColor = labelsColor
            value1Label.textColor = labelsColor
            value10Label.textColor = labelsColor
            value100Label.textColor = labelsColor
            value1000Label.textColor = labelsColor
            value10000Label.textColor = labelsColor
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
            linesLayer.strokeColor = lineColor.cgColor
            fillLayer.fillColor = lineColor.withAlphaComponent(0.3).cgColor
        }
    }
    
    @objc public func add(value: CGFloat, at timeInterval: TimeInterval) {
        // Ignore values that come in after max seconds
        guard timeInterval < RMBTSpeedGraphView.RMBTSpeedGraphViewSeconds else { return }
        
        let p = CGPoint(x: timeInterval, y: value)
        //Filter duplicates
        if let point = chartPoints.first(where: { $0.x == p.x }),
           let index = chartPoints.firstIndex(of: point) {
           if point.x < p.x {
               chartPoints[index] = p
           }
        } else {
            chartPoints.append(p)
        }
        
        self.calculatePath()
    }
    
    @objc public func clear() {
        chartPoints.removeAll()
        linesLayer.path = UIBezierPath().cgPath
        fillLayer.path = nil
    }
    
    private func setup() {
        self.backgroundColor = UIColor.clear
        self.backgroundImage = self.markedBackgroundImage()
    
        backgroundLayer.frame = self.graphRect
        backgroundLayer.contents = backgroundImage?.cgImage
        
        self.layer.addSublayer(backgroundLayer)
        
        linesLayer.lineWidth = 1.0
        linesLayer.strokeColor = self.lineColor.cgColor
        linesLayer.lineCap = CAShapeLayerLineCap.round
        linesLayer.fillColor = nil
        linesLayer.frame = self.graphRect
        
        self.layer.addSublayer(linesLayer)

        fillLayer.lineWidth = 0.0
        fillLayer.fillColor = self.lineColor.withAlphaComponent(0.3).cgColor
        
        fillLayer.frame = self.graphRect
        self.layer.insertSublayer(fillLayer, below: linesLayer)
        
        widthPerSecond = self.graphRect.width / RMBTSpeedGraphView.RMBTSpeedGraphViewSeconds
        
        self.addSubview(startIntervalLabel)
        NSLayoutConstraint.activate([
            startIntervalLabel.leftAnchor.constraint(equalTo: self.leftAnchor, constant: 8),
            startIntervalLabel.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: 0),
            startIntervalLabel.heightAnchor.constraint(equalToConstant: 11)
        ])
        
        self.addSubview(endIntervalLabel)
        NSLayoutConstraint.activate([
            endIntervalLabel.rightAnchor.constraint(equalTo: self.rightAnchor, constant: -labelWidth),
            endIntervalLabel.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: 0),
            endIntervalLabel.heightAnchor.constraint(equalToConstant: 11)
        ])

        self.value10000TopConstraint = addValueLabel(value10000Label)
        self.value1000TopConstraint = addValueLabel(value1000Label)
        self.value100TopConstraint = addValueLabel(value100Label)
        self.value10TopConstraint = addValueLabel(value10Label)
        self.value1TopConstraint = addValueLabel(value1Label)
        
        updateUI()
    }

    func addValueLabel(_ label: UILabel) -> NSLayoutConstraint {
        self.addSubview(label)
        let constraint = label.topAnchor.constraint(equalTo: self.topAnchor, constant: 0)
        NSLayoutConstraint.activate([
            label.rightAnchor.constraint(equalTo: self.rightAnchor, constant: 0),
            constraint,
            label.heightAnchor.constraint(equalToConstant: labelHeight),
            label.widthAnchor.constraint(equalToConstant: labelWidth)
        ])
        
        return constraint
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
        fillLayer.frame = self.graphRect
        linesLayer.frame = self.graphRect
        updateUI()
        calculatePath()
    }
    
    func updateUI() {
        widthPerSecond = self.graphRect.width / RMBTSpeedGraphView.RMBTSpeedGraphViewSeconds
        self.backgroundImage = self.markedBackgroundImage()
        backgroundLayer.contents = backgroundImage?.cgImage
        let size = self.graphRect.size
        let countLines = GAUGE_PARTS
        let topOffset = CGFloat(2)
        let offset = size.height / CGFloat(countLines)
        value10000TopConstraint?.constant = topOffset + offset * 0
        value1000TopConstraint?.constant = topOffset + offset * 1
        value100TopConstraint?.constant = topOffset + offset * 2
        value10TopConstraint?.constant = topOffset + offset * 3
        value1TopConstraint?.constant = topOffset + offset * 4
    }
    
    private func markedBackgroundImage() -> UIImage? {
        let size = self.graphRect.size
        UIGraphicsBeginImageContextWithOptions(size, false, 0.0 /* device main screen*/);
        let context = UIGraphicsGetCurrentContext();

        context?.setLineWidth(1 / UIScreen.main.scale)
        context?.setStrokeColor(graphLinesColor.cgColor)
        let countLines = Int(GAUGE_PARTS.rounded())
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

extension RMBTSpeedGraphView {
    @objc internal func getChartWidth() -> CGFloat {
        return 1
    }
    
    internal func getChartHeight() -> CGFloat {
        return self.graphRect.height
    }
    
    internal func calculatePath() {
        guard chartPoints.count > 1 else { return }
        let pathStroke = UIBezierPath()
        var lX: CGFloat = 0
        var lY: CGFloat = 0
        
        pathStroke.move(to: CGPoint(x: getChartWidth() * chartPoints[0].x * widthPerSecond, y: getChartHeight() - (getChartHeight() * chartPoints[0].y)))
        
        for index in 1..<chartPoints.count {
            let currentPointX = getChartWidth() * chartPoints[index].x * widthPerSecond
            let currentPointY = getChartHeight() - (getChartHeight() * chartPoints[index].y)
            
            let previousPointX = getChartWidth() * chartPoints[index - 1].x * widthPerSecond
            let previousPointY = getChartHeight() - (getChartHeight() * chartPoints[index - 1].y)
            
            // Distance between currentPoint and previousPoint
            let firstDistance = sqrt(pow(currentPointX - previousPointX, 2.0) + pow(currentPointY - previousPointY, 2.0))
            
            // Minimum is used to avoid going too much right
            let firstX = min(previousPointX + lX * firstDistance, (previousPointX + currentPointX) / 2)
            let firstY = previousPointY + lY * firstDistance

            let nextPointX = getChartWidth() * chartPoints[(index + 1 < chartPoints.count) ?  index + 1 : index].x * widthPerSecond
            let nextPointY = getChartHeight() - (getChartHeight() * chartPoints[(index + 1 < chartPoints.count) ? index + 1 : index].y)
            
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

        linesLayer.path = pathStroke.cgPath
        
        let fillPath = UIBezierPath()
        fillPath.append(pathStroke)
        fillPath.addLine(to: CGPoint(x: getChartWidth() * chartPoints[chartPoints.count - 1].x * widthPerSecond, y: getChartHeight()))
        fillPath.addLine(to: CGPoint(x: getChartWidth() * chartPoints[0].x * widthPerSecond, y: getChartHeight()))
        fillLayer.path = fillPath.cgPath
    }
}

class RMBTHistorySpeedGraphView: RMBTSpeedGraphView {
    internal override var widthPerSecond: CGFloat {
        return 1.0
    }
    
    internal override func getChartWidth() -> CGFloat {
        return self.graphRect.width
    }
    
    public func add(point: CGPoint) {
        chartPoints.append(point)
        self.calculatePath()
    }
}
